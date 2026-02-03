{
  stdenv,
  fetchFromGitHub,
  lib,
  makeWrapper,
  fzf,
  jq,
  git,
  installShellFiles,
}:

stdenv.mkDerivation rec {
  pname = "git-worktree-switcher";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "yankeexe";
    repo = "git-worktree-switcher";
    rev = version;  # Tags don't have 'v' prefix
    hash = "sha256-BUfb7nj7t2r6Kd1VbQWptL+p+zKHy8bWr612FExJoEE=";
  };

  nativeBuildInputs = [ makeWrapper installShellFiles ];

  installPhase = ''
    runHook preInstall

    install -Dm755 wt $out/bin/wt

    # Wrap with runtime dependencies
    wrapProgram $out/bin/wt \
      --prefix PATH : ${lib.makeBinPath [ fzf jq git ]}

    # Install shell completions
    installShellCompletion --zsh completions/_wt_completion
    installShellCompletion --bash completions/wt_completion
    installShellCompletion --fish completions/wt.fish

    runHook postInstall
  '';

  meta = with lib; {
    description = "Switch between git worktrees with speed";
    homepage = "https://github.com/yankeexe/git-worktree-switcher";
    license = licenses.mit;
    mainProgram = "wt";
  };
}
