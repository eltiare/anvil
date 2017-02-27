require "json"
require "openssl"
require 'base64'
require 'base16'


def base64_le(data)
  txt_data = if data.respond_to?(:entries)
    JSON.dump(data)
  else
    data
  end
  Base64.urlsafe_encode64(txt_data).delete('=')
end

def thumbprint
  jwk = JSON.dump(header[:jwk])
  puts jwk
  bin = Digest::SHA256.digest jwk
  base64_le(bin)
end

def client_key
  @client_key ||= begin
    client_key_path = File.expand_path('acme_key/private.key')
    OpenSSL::PKey::RSA.new IO.read(client_key_path)
  end
end

def header
  @header ||= {
    alg: 'RS256',
    jwk: {
      e: base64_le(client_key.e.to_s(2)),
      kty: 'RSA',
      n: base64_le(client_key.n.to_s(2))
    }
  }
end

def private_public_key
  key_path = File.expand_path('certs/server.key')
  key = OpenSSL::PKey::RSA.new IO.read(key_path)
  key.public_key
end

puts private_public_key.to_s
