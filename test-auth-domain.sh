#!/bin/sh

RSA_KEY=acme_key/temp.key
mix escript.build && ./ndc authorize-domain accentuate.me -k=$RSA_KEY
# mix escript.build && ./ndc register jnicoll@accentuate.me --staging -k=$RSA_KEY
