#!/bin/bash

# エラーハンドリング
set -e

# 色の定義
GREEN='\033[0;32m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[1;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ステータス表示用の関数
status_msg() {
    echo -e "${BLUE}[*]${NC} $1"
}

success_msg() {
    echo -e "${GREEN}[✓]${NC} $1"
}

error_msg() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

# ロゴ表示
display_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
    ███████╗███╗   ███╗██╗  ██╗    ███╗   ██╗██╗██╗  ██╗
    ╚══███╔╝████╗ ████║██║ ██╔╝    ████╗  ██║██║╚██╗██╔╝
      ███╔╝ ██╔████╔██║█████╔╝     ██╔██╗ ██║██║ ╚███╔╝ 
     ███╔╝  ██║╚██╔╝██║██╔═██╗     ██║╚██╗██║██║ ██╔██╗ 
    ███████╗██║ ╚═╝ ██║██║  ██╗    ██║ ╚████║██║██╔╝ ██╗
    ╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝
                ZMK-Nix Build Environment
EOF
    echo -e "${NC}"
}

# システム情報表示
show_system_info() {
    echo -e "${PURPLE}╔════ SYSTEM INFORMATION ═══════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} ${CYAN}User:${NC}     $(whoami)"
    echo -e "${PURPLE}║${NC} ${CYAN}Date:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${PURPLE}║${NC} ${CYAN}System:${NC}   $(uname -sr)"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
}

# build.yamlの解析
parse_build_yaml() {
    status_msg "Analyzing build.yaml configuration..."
    
    if [ ! -f "build.yaml" ]; then
        error_msg "build.yaml not found in current directory"
        exit 1
    fi

    SHIELDS=()
    SNIPPETS=()
    while IFS= read -r line; do
        if [[ $line =~ shield:\ *(.*) ]]; then
            shield="${BASH_REMATCH[1]}"
            if [[ $shield != "settings_reset" ]]; then
                SHIELDS+=("$shield")
            fi
        elif [[ $line =~ snippet:\ *(.*) ]]; then
            SNIPPETS+=("${BASH_REMATCH[1]}")
        fi
    done < build.yaml

    SHIELD_BASE=""
    if [ ${#SHIELDS[@]} -gt 0 ]; then
        SHIELD_BASE=$(echo "${SHIELDS[0]}" | sed 's/_[LR]$//')
    fi

    PARTS=()
    for shield in "${SHIELDS[@]}"; do
        part=$(echo "$shield" | grep -o '[LR]$')
        if [ ! -z "$part" ]; then
            PARTS+=("\"$part\"")
        fi
    done

    success_msg "Configuration loaded successfully"
    echo "Shield Base: $SHIELD_BASE"
    echo "Parts: ${PARTS[*]}"
    echo "Snippets: ${SNIPPETS[*]:-zmk-usb-logging}"
}

# Nixのチェック
check_nix() {
    status_msg "Checking Nix installation..."
    if ! command -v nix &> /dev/null; then
        error_msg "Nix not found. Installing..."
        curl -L https://nixos.org/nix/install | sh
        . ~/.nix-profile/etc/profile.d/nix.sh
    fi
    success_msg "Nix installation verified"
}

# flake.nixの生成
generate_flake_nix() {
    status_msg "Generating flake.nix..."
    cat > flake.nix << EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zmk-nix }: let
    forAllSystems = nixpkgs.lib.genAttrs (nixpkgs.lib.attrNames zmk-nix.packages);
  in {
    packages = forAllSystems (system: rec {
      default = firmware;

      firmware = zmk-nix.legacyPackages.\${system}.buildSplitKeyboard {
        name = "firmware";
        src = nixpkgs.lib.sourceFilesBySuffices self [ ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi" ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig" ];
        board = "seeeduino_xiao_ble";
        shield = "${SHIELD_BASE}_%PART%";
        parts = [ ${PARTS[@]} ];
        snippets = [ "${SNIPPETS[@]:-zmk-usb-logging}" ];
        enableZmkStudio = true;
        zephyrDepsHash = "sha256-YkNPlLZcCguSYdNGWzFNfZbJgmZUhvpB7DRnj++XKqQ=";
        meta = {
          description = "ZMK firmware";
          license = nixpkgs.lib.licenses.mit;
          platforms = nixpkgs.lib.platforms.all;
        };
      };

      flash = zmk-nix.packages.\${system}.flash.override { inherit firmware; };
      update = zmk-nix.packages.\${system}.update;
    });

    devShells = forAllSystems (system: {
      default = zmk-nix.devShells.\${system}.default;
    });
  };
}
EOF
    success_msg "flake.nix generated"
}

# メイン処理
main() {
    clear
    display_logo
    show_system_info

    # Nixチェック
    check_nix

    # build.yaml解析
    parse_build_yaml

    # ZMK-Nixテンプレート初期化
    status_msg "Initializing ZMK-Nix template..."
    nix flake init --template github:lilyinstarlight/zmk-nix
    success_msg "ZMK-Nix template initialized"

    # flake.nix生成
    generate_flake_nix

    # .gitignoreの更新
    status_msg "Updating .gitignore..."
    {
        echo "result"
        echo ".direnv"
        echo ".envrc"
    } >> .gitignore
    sort -u .gitignore -o .gitignore
    success_msg ".gitignore updated"

    # ビルド実行
    status_msg "Building firmware..."
    if ! nix build 2> build_error.log; then
        error_output=$(cat build_error.log)
        if echo "$error_output" | grep -q "hash mismatch"; then
            status_msg "Hash mismatch detected. Attempting to fix..."
            new_hash=$(echo "$error_output" | grep "got:" | awk '{print $2}')
            if [ ! -z "$new_hash" ]; then
                sed -i "s/zephyrDepsHash = \".*\"/zephyrDepsHash = \"$new_hash\"/" flake.nix
                echo "Updated hash: $new_hash"
                status_msg "Retrying build..."
                nix build
            fi
        else
            cat build_error.log
            exit 1
        fi
    fi
    rm -f build_error.log
    success_msg "Firmware built successfully"

    echo -e "\n${GREEN}┌────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}     🎉 Setup Complete! 🎉           ${GREEN}│${NC}"
    echo -e "${GREEN}└────────────────────────────────────────┘${NC}\n"

    echo "Build artifacts location: ./result/"
    echo -e "\n${CYAN}Next steps:${NC}"
    echo -e "1. Configure your keymap in ${WHITE}config/${NC} directory"
    echo -e "2. Commit and push your changes"
    echo -e "3. Run ${WHITE}nix build${NC} to rebuild firmware"
}

# スクリプトの実行
main "$@"