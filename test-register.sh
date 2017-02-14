#!/bin/sh

RSA_KEY=acme_key/temp.key
mix escript.build && openssl genrsa -out $RSA_KEY 2048 && ./ndc register jnicoll@accentuate.me --staging -k=$RSA_KEY
# mix escript.build && ./ndc register jnicoll@accentuate.me --staging -k=$RSA_KEY
