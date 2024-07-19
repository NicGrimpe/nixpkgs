{ lib, buildGoModule, fetchFromGitHub, testers, vals }:

buildGoModule rec {
  pname = "vals";
  version = "0.37.3";

  src = fetchFromGitHub {
    rev = "v${version}";
    owner = "helmfile";
    repo = pname;
    sha256 = "sha256-RCvqoikROFpFvza24PGocdxFaOI6hZLSy3Jnag7Oz4s=";
  };

  vendorHash = "sha256-iKfNAQRsVUjhUmDH/HevnDnocQm4k9jEfW40+AncojM=";

  proxyVendor = true;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  # Tests require connectivity to various backends.
  doCheck = false;

  passthru.tests.version = testers.testVersion {
    package = vals;
    command = "vals version";
  };

  meta = with lib; {
    description = "Helm-like configuration values loader with support for various sources";
    mainProgram = "vals";
    license = licenses.asl20;
    homepage = "https://github.com/helmfile/vals";
    changelog = "https://github.com/helmfile/vals/releases/v${version}";
    maintainers = with maintainers; [ stehessel ];
  };
}
