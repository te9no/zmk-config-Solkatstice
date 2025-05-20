#!/bin/bash
# スクリプト名: setup-zmk-nix.sh
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
# リポジトリ情報
REPO_URL="https://github.com/te9no/zmk-config-roBa"
REPO_OWNER="te9no"
REPO_NAME="zmk-config-roBa"
CURRENT_USER="te9no"
CURRENT_DATE="2025-05-20 09:46:37"

# アニメーション関数
show_loading() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r${CYAN}[%c]${NC} " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r"
}

# ハッカーライクな表示関数
hack_print() {
    local text=$1
    local delay=${2:-0.02}
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# アスキーアートロゴ
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
    echo -e "${PURPLE}║${NC} ${CYAN}User:${NC}     $CURRENT_USER"
    echo -e "${PURPLE}║${NC} ${CYAN}Date:${NC}     $CURRENT_DATE"
    echo -e "${PURPLE}║${NC} ${CYAN}System:${NC}   $(uname -sr)"
    echo -e "${PURPLE}║${NC} ${CYAN}Repo:${NC}     $REPO_URL"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${NC}\n"
}

# プログレスバー
show_progress() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r${BLUE}[${CYAN}"
    for ((i = 0; i < completed; i++)); do printf "█"; done
    for ((i = 0; i < remaining; i++)); do printf "░"; done
    printf "${BLUE}] ${WHITE}%d%%${NC}" $percentage
}

# build.yamlから設定を解析する関数
parse_build_yaml() {
    hack_print "Analyzing build.yaml configuration..." 0.03
    
    if [ ! -f "build.yaml" ]; then
        echo -e "${RED}[✗] ERROR: build.yaml not found in current directory${NC}"
        exit 1
    }

    # シールドの設定を解析
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

    # シールドのベース名を抽出
    SHIELD_BASE=""
    if [ ${#SHIELDS[@]} -gt 0 ]; then
        SHIELD_BASE=$(echo "${SHIELDS[0]}" | sed 's/_[LR]$//')
    fi

    # パーツリストを生成
    PARTS=()
    for shield in "${SHIELDS[@]}"; do
        part=$(echo "$shield" | grep -o '[LR]$')
        if [ ! -z "$part" ]; then
            PARTS+=("\"$part\"")
        fi
    done

    echo -e "${GREEN}[✓]${NC} Configuration loaded successfully"
    hack_print "Shield Base: $SHIELD_BASE" 0.02
    hack_print "Parts: ${PARTS[*]}" 0.02
    hack_print "Snippets: ${SNIPPETS[*]:-zmk-usb-logging}" 0.02
}

# Nixのチェック
check_nix() {
    if ! command -v nix &> /dev/null; then
        echo -e "${YELLOW}[!] Nix not found. Installing...${NC}"
        curl -L https://nixos.org/nix/install | sh
        . ~/.nix-profile/etc/profile.d/nix.sh
    fi
    echo -e "${GREEN}[✓]${NC} Nix installation verified"
}

# flake.nixの生成
generate_flake_nix() {
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
}

# エラー出力からhash値を抽出する関数
extract_hash() {
    echo "$1" | grep "got:" | awk '{print $2}'
}

# メイン処理
main() {
    clear
    display_logo
    show_system_info
    
    total_steps=5
    current_step=0

    # Nixチェック
    ((current_step++))
    show_progress $current_step $total_steps
    check_nix

    # build.yaml解析
    ((current_step++))
    show_progress $current_step $total_steps
    parse_build_yaml

    # ZMK-Nixテンプレート初期化
    ((current_step++))
    show_progress $current_step $total_steps
    hack_print "Initializing ZMK-Nix template..." 0.02
    nix flake init --template github:lilyinstarlight/zmk-nix

    # flake.nix生成
    ((current_step++))
    show_progress $current_step $total_steps
    hack_print "Generating flake.nix configuration..." 0.02
    generate_flake_nix

    # .gitignoreの更新
    echo -e "\n${BLUE}[*]${NC} Updating .gitignore..."
    {
        echo "result"
        echo ".direnv"
        echo ".envrc"
    } >> .gitignore
    sort -u .gitignore -o .gitignore

    # ビルド実行
    ((current_step++))
    show_progress $current_step $total_steps
    hack_print "Building firmware..." 0.02
    if ! nix build 2> build_error.log; then
        error_output=$(cat build_error.log)
        if echo "$error_output" | grep -q "hash mismatch"; then
            echo -e "${YELLOW}[!] Hash mismatch detected. Attempting to fix...${NC}"
            new_hash=$(extract_hash "$error_output")
            if [ ! -z "$new_hash" ]; then
                sed -i "s/zephyrDepsHash = \".*\"/zephyrDepsHash = \"$new_hash\"/" flake.nix
                hack_print "Updated hash: $new_hash" 0.02
                hack_print "Retrying build..." 0.02
                nix build
            fi
        else
            cat build_error.log
            exit 1
        fi
    fi
    rm -f build_error.log

    # 完了メッセージ
    echo -e "\n${GREEN}┌────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}     🎉 Setup Complete! 🎉           ${GREEN}│${NC}"
    echo -e "${GREEN}└────────────────────────────────────────┘${NC}\n"

    hack_print "Build artifacts location: ./result/" 0.03
    echo -e "\n${CYAN}Next steps:${NC}"
    echo -e "1. Configure your keymap in ${WHITE}config/${NC} directory"
    echo -e "2. Commit and push your changes"
    echo -e "3. Run ${WHITE}nix build${NC} to rebuild firmware"
}

# スクリプトの実行
main "$@"