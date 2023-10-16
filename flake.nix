{
  description = "A very basic flake";

  outputs = {
    self,
    nixpkgs,
  }: {
    devShell.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      packages = [
        nixpkgs.legacyPackages.x86_64-linux.typst-lsp
        nixpkgs.legacyPackages.x86_64-linux.typst
      ];
    };
  };
}
