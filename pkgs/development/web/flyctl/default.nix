{ lib, buildGoModule, fetchFromGitHub, testers, flyctl, installShellFiles }:

buildGoModule rec {
  pname = "flyctl";
  version = "0.1.131";

  src = fetchFromGitHub {
    owner = "superfly";
    repo = "flyctl";
    rev = "v${version}";
    hash = "sha256-q24QQExHsIUkMQBhIdYN9ra6tSPfB21SxXnZzVJIpJk=";
  };

  vendorHash = "sha256-UHG0pUJzA3I8uBbll+4fEpwpEvNBxoQYKr8wuupc8NQ=";

  subPackages = [ "." ];

  ldflags = [
    "-s" "-w"
    "-X github.com/superfly/flyctl/internal/buildinfo.buildDate=1970-01-01T00:00:00Z"
    "-X github.com/superfly/flyctl/internal/buildinfo.buildVersion=${version}"
  ];
  tags = ["production"];

  nativeBuildInputs = [ installShellFiles ];

  patches = [ ./disable-auto-update.patch ];

  preBuild = ''
    go generate ./...
  '';

  preCheck = ''
    HOME=$(mktemp -d)
  '';

  postCheck = ''
    go test ./... -ldflags="-X 'github.com/superfly/flyctl/internal/buildinfo.buildDate=1970-01-01T00:00:00Z'"
  '';

  postInstall = ''
    installShellCompletion --cmd flyctl \
      --bash <($out/bin/flyctl completion bash) \
      --fish <($out/bin/flyctl completion fish) \
      --zsh <($out/bin/flyctl completion zsh)
    ln -s $out/bin/flyctl $out/bin/fly
  '';

  passthru.tests.version = testers.testVersion {
    package = flyctl;
    command = "HOME=$(mktemp -d) flyctl version";
    version = "v${flyctl.version}";
  };

  meta = with lib; {
    description = "Command line tools for fly.io services";
    downloadPage = "https://github.com/superfly/flyctl";
    homepage = "https://fly.io/";
    license = licenses.asl20;
    maintainers = with maintainers; [ aaronjanse adtya jsierles techknowlogick viraptor ];
    mainProgram = "flyctl";
  };
}
