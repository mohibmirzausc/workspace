final: prev: {
  shopify-cli = prev.shopify-cli.overrideAttrs (oldAttrs: rec {
    version = "3.90.1";

    src = prev.fetchFromGitHub {
      owner = "shopify";
      repo = "cli";
      tag = version;
      hash = "sha256-K0kuHPcF+ElmnQ+Fa1e2Vo5zfI7v9Fz/oyzTAw2KwQM=";
    };

    pnpmDeps = prev.fetchPnpmDeps {
      pname = "shopify";
      inherit version src;
      fetcherVersion = 2;
      hash = "sha256-aa2S/1f5illHtTT/ubxSs4xW2tHLmWIkUU8RC4A4le0=";
    };
  });
}
