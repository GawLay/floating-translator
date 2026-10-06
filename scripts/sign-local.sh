#!/bin/zsh
# Reuse a certificate so local updates satisfy the same macOS privacy identity.
set -euo pipefail
umask 077

ft_app_path=${1:?Usage: sign-local.sh app-path}
ft_signing_dir=${FLOATING_TRANSLATOR_SIGNING_DIR:-"$HOME/Library/Application Support/Floating Translator/Signing"}
ft_keychain="$ft_signing_dir/local.keychain-db"
ft_certificate="$ft_signing_dir/certificate.pem"
ft_password_file="$ft_signing_dir/keychain-password"
ft_identity='Floating Translator Local Development'
ft_original_keychains=("${(@f)$(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')}")
ft_new_identity=false
ft_setup_complete=false
ft_temporary_dir=''

cleanup() {
  security list-keychains -d user -s "${ft_original_keychains[@]}" >/dev/null 2>&1 || true
  security lock-keychain "$ft_keychain" >/dev/null 2>&1 || true
  if [[ -n "$ft_temporary_dir" ]]; then rm -rf "$ft_temporary_dir"; fi
  if [[ "$ft_new_identity" == true && "$ft_setup_complete" == false ]]; then
    security remove-trusted-cert "$ft_certificate" >/dev/null 2>&1 || true
    security delete-keychain "$ft_keychain" >/dev/null 2>&1 || true
    rm -f "$ft_certificate" "$ft_password_file"
  fi
}
trap cleanup EXIT

mkdir -p "$ft_signing_dir"
chmod 700 "$ft_signing_dir"
if [[ ! -f "$ft_keychain" ]]; then
  # Never rotate a partially missing identity silently: that loses privacy grants.
  if [[ -e "$ft_certificate" || -e "$ft_password_file" ]]; then
    print -u2 'The local signing identity is incomplete. Restore its keychain before building.'
    exit 1
  fi
  ft_new_identity=true
  ft_temporary_dir=$(mktemp -d "$ft_signing_dir/setup.XXXXXX")
  openssl rand -hex 32 > "$ft_password_file"
  cat > "$ft_temporary_dir/certificate.cnf" <<'CERT'
[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions
[subject]
CN = Floating Translator Local Development
[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CERT
  openssl req -new -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
    -config "$ft_temporary_dir/certificate.cnf" \
    -keyout "$ft_temporary_dir/private-key.pem" -out "$ft_certificate" >/dev/null 2>&1
  openssl pkcs12 -export -inkey "$ft_temporary_dir/private-key.pem" \
    -in "$ft_certificate" -out "$ft_temporary_dir/identity.p12" \
    -passout "file:$ft_password_file"
  ft_password=$(cat "$ft_password_file")
  security create-keychain -p "$ft_password" "$ft_keychain"
  security set-keychain-settings -lut 600 "$ft_keychain"
  security unlock-keychain -p "$ft_password" "$ft_keychain"
  security import "$ft_temporary_dir/identity.p12" -k "$ft_keychain" \
    -P "$ft_password" -x -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool: -s -k "$ft_password" "$ft_keychain" >/dev/null
  # User-level trust for this exact certificate's code-signing use only.
  # This does not add a TLS root or change the System keychain.
  security add-trusted-cert -r trustRoot -p codeSign -k "$ft_keychain" "$ft_certificate"
  ft_setup_complete=true
else
  [[ -f "$ft_certificate" && -f "$ft_password_file" ]] || {
    print -u2 'The local signing certificate or password file is missing. Restore the signing directory.'
    exit 1
  }
  ft_password=$(cat "$ft_password_file")
  security unlock-keychain -p "$ft_password" "$ft_keychain"
fi

# codesign also requires the private keychain in the search list. Restore the
# user's original list immediately after signing, and lock this keychain again.
security list-keychains -d user -s "${ft_original_keychains[@]}" "$ft_keychain"
codesign --force --timestamp=none --keychain "$ft_keychain" --sign "$ft_identity" "$ft_app_path"
codesign --verify --deep --strict "$ft_app_path"
print 'Signed with the persistent local development identity.'
