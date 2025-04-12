{
  inputs =
  {
    # Main repository
    # This will pull in a lot of unrelated indirect flake inputs (e.g., misskey).
    # If you think this is a problem, you can fork my repo and remove them
    chn-nixos.url = "github:CHN-beta/nixos/production";
  };
  outputs = inputs:
  {
    # It is nencessary to use my fork of nixpkgs,
    #  from chn-nixos.inputs.nixpkgs or from github:CHN-beta/nixpkgs/nixos-24.11
    nixosConfigurations.test-machine = inputs.chn-nixos.inputs.nixpkgs.lib.nixosSystem
    {
      system = "x86_64-linux";
      specialArgs.topInputs = inputs;
      modules =
      [({pkgs, ...}@inputs: {
        config =
        {
          # You have two way to setup nixpkgs, choose only one of them
          # First way, setup it using function provided by chn-nixos
          # this will pull in a lot of unrelated modifications, which you may not want, but may be the easiest way
          nixpkgs = import "${inputs.topInputs.chn-nixos}/modules/system/nixpkgs/buildNixpkgsConfig.nix"
          {
            inputs =
              inputs // { topInputs = inputs.topInputs.chn-nixos.inputs // { self = inputs.topInputs.chn-nixos; }; };
            nixpkgs =
            {
              # cpu arch
              march = "znver4";
              cuda =
              {
                # tell nvhpc build against which gpu
                # it should cover all the gpus you will run the code on,
                #   no harm to add more (other than longer build time and larger package size)
                # see https://en.wikipedia.org/wiki/CUDA#GPUs_supported
                #   for the list of cuda capabilities and the corresponding GPUs
                capabilities =
                [
                  # p5000 p400
                  "6.1"
                  # 2080 Ti
                  "7.5"
                  # 3090
                  "8.6"
                  # 4060 4090
                  "8.9"
                ];
                # forward compatibility support is not implemented yet (maybe it is easy to implement but I am too lazy)
                forwardCompat = false;
              };
              # not related to goal of this flake, but must be set to null
              nixRoot = null;
            };
          };

          # Second way, pull in overlay from chn-nixos and then manually set up nixpkgs
          # this way is more flexible, but some packages will not build.
          # For example, vasp compiled using intel oneapi `vasp.intel` needs bscpkgs overlay,
          #   which will not work in this way, but works in the first way.
          # nixpkgs =
          # {
            # pull in overlay, it will add a package set named `localPackages`
            # overlays = [ inputs.topInputs.chn-nixos.overlays.default ];
            # if you do not like the name `localPackages`, you can modify it, for example, `hpc-pkgs`:
            # overlays = [(final: prev: { hpc-pkgs = (inputs.chn-nixos.overlays.default final prev).localPackages; })];
            # Then setup nixpkgs
            # config =
            # {
              # I am not sure if this is necessary, I always set it to true
              # allowUnfree = true;
              # set your cpu micro arch, affecting default stdenv
              # you may meet some build failures after setting this.
              # To resolve this issue, some patches have been added to my fork of nixpkgs,
              #  some could be find in "${inputs.nixos}/modules/system/nixpkgs/buildNixpkgsConfig.nix",
              # hostPlatform = { system = "x86_64-linux"; gcc = { arch = "znver4"; tune = "znver4"; }; };

              # cuda support is necessary for nvhpc
              # cudaSupport = true;
              # it is also necessary to set cudaCapabilities, to tell nvhpc build against which gpu
              # it should cover all the gpus you will run the code on,
              #   no harm to add more (other than longer build time and larger package size)
              # see https://en.wikipedia.org/wiki/CUDA#GPUs_supported
              #  for the list of cuda capabilities and the corresponding GPUs
              # cudaCapabilities =
              # [
                # p5000 p400
                # "6.1"
                # 2080 Ti
                # "7.5"
                # 3090
                # "8.6"
                # 4060 4090
                # "8.9"
              # ];
              # I have not implement forward compatibility for nvhpc
              # cudaForwardCompat = false;
              # set cpu arch for nvhpc, in most cases it should be the same as gcc.arch,
              # but in rare cases (e.g. cpu is too new to be recognized by nvhpc), you should set it to a lower value
              # nvhpcArch = "znver4";

              # set arch for oneapi compilers.
              # just like nvhpc, it should be the same as gcc.arch other than rare cases
              # oneapiArch = "znver4";
            # };
          # };

          # now you can use localPackages.nvhpcPackages etc.
          environment.systemPackages =
            # let's build hello using nvhpc
            (with inputs.pkgs; [(hello.override { inherit (localPackages.nvhpcPackages) stdenv; })])
            # and vasp, using nvhpc and oneapi
            ++ (with inputs.pkgs.localPackages.vasp; [ nvidia intel ]);

          # other system configurations...
          fileSystems =
          {
            "/" =
            {
              device = "/dev/disk/by-partlabel/root";
              fsType = "btrfs";
              options = [ "compress-force=zstd" "subvol=/nix/rootfs/current" "acl" "noatime" ];
            };
            "/boot" =
            {
              device = "/dev/disk/by-partlabel/boot";
              fsType = "vfat";
              options = [ "noatime" ];
            };
          };
          boot.loader =
          {
            grub = { enable = true; useOSProber = false; device = "nodev"; efiSupport = true; };
            efi.canTouchEfiVariables = true;
          };
          system.stateVersion = "24.11";
        };
      })];
    };

    # You could also build single packages instead of a whole system
    packages.x86_64-linux.nvhpc-hello = with inputs.self.nixosConfigurations.test-machine.pkgs;
      hello.override { inherit (localPackages.nvhpcPackages) stdenv; };
  };
}

# build it using:
# nom build .#nixosConfigurations.test-machine.config.system.build.toplevel
# or
# nix build .#nvhpc-hello
