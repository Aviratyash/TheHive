#!/usr/bin/env bash
# =============================================================================
#  ████████╗██╗  ██╗███████╗    ██╗  ██╗██╗██╗   ██╗███████╗
#     ██╔══╝██║  ██║██╔════╝    ██║  ██║██║██║   ██║██╔════╝
#     ██║   ███████║█████╗      ███████║██║██║   ██║█████╗
#     ██║   ██╔══██║██╔══╝      ██╔══██║██║╚██╗ ██╔╝██╔══╝
#     ██║   ██║  ██║███████╗    ██║  ██║██║ ╚████╔╝ ███████╗
#     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝
#  Automated Setup Script — TheHive 5 + Cassandra + Elasticsearch
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
TICK="${GREEN}✔${RESET}"; CROSS="${RED}✘${RESET}"
ARROW="${CYAN}▶${RESET}"; WARN="${YELLOW}⚠${RESET}"

banner() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║                                                                  ║"
    echo "  ║   ████████╗██╗  ██╗███████╗    ██╗  ██╗██╗██╗   ██╗███████╗   ║"
    echo "  ║      ██╔══╝██║  ██║██╔════╝    ██║  ██║██║██║   ██║██╔════╝   ║"
    echo "  ║      ██║   ███████║█████╗      ███████║██║██║   ██║█████╗     ║"
    echo "  ║      ██║   ██╔══██║██╔══╝      ██╔══██║██║╚██╗ ██╔╝██╔══╝    ║"
    echo "  ║      ██║   ██║  ██║███████╗    ██║  ██║██║ ╚████╔╝ ███████╗  ║"
    echo "  ║      ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝  ║"
    echo "  ║                                                                  ║"
    echo "  ║         Automated Installer  ·  TheHive 5 + Stack               ║"
    echo "  ║                                                                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

section() {
    echo ""
    echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${BLUE}│  ${WHITE}$1${BLUE}$(printf '%*s' $((51 - ${#1})) '')│${RESET}"
    echo -e "${BOLD}${BLUE}└─────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

step()    { echo -e "  ${ARROW} ${WHITE}$1${RESET}"; }
ok()      { echo -e "  ${TICK} ${GREEN}$1${RESET}"; }
warn()    { echo -e "  ${WARN} ${YELLOW}$1${RESET}"; }
fail()    { echo -e "  ${CROSS} ${RED}$1${RESET}"; exit 1; }
divider() { echo -e "  ${DIM}──────────────────────────────────────────────────────${RESET}"; }

prompt_input() {
    local label="$1" default="$2" var_name="$3" secret="${4:-false}" value
    echo -e ""
    echo -e "  ${MAGENTA}┌─ ${WHITE}${label}${RESET}"
    if [[ "$secret" == "true" ]]; then
        echo -ne "  ${MAGENTA}└─▶ ${CYAN}(hidden)${RESET} "
        read -s -r value; echo ""
    else
        echo -ne "  ${MAGENTA}└─▶ ${DIM}[default: ${default}]${RESET} "
        read -r value
    fi
    [[ -z "$value" ]] && value="$default"
    eval "${var_name}='${value}'"
}

prompt_yn() {
    local label="$1" default="${2:-y}" var_name="$3" hint value
    if [[ "$default" == "y" ]]; then hint="Y/n"; else hint="y/N"; fi
    echo -e ""
    echo -ne "  ${YELLOW}?${RESET} ${WHITE}${label}${RESET} ${DIM}[${hint}]${RESET} "
    read -r value
    value="${value:-$default}"
    eval "${var_name}='${value,,}'"
}

run_step() {
    local description="$1"; shift
    echo -ne "  ${ARROW} ${WHITE}${description}...${RESET} "
    if "$@" > /tmp/thehive_install.log 2>&1; then
        echo -e "${TICK}"
    else
        echo -e "${CROSS}"
        echo -e "\n  ${RED}Error output:${RESET}"
        tail -20 /tmp/thehive_install.log | sed 's/^/    /'
        fail "Step failed: ${description}"
    fi
}

summary_line() { printf "  ${DIM}%-32s${RESET} ${WHITE}%s${RESET}\n" "$1" "$2"; }

# ── PRE-FLIGHT ────────────────────────────────────────────────────────────────

check_root() { if [[ $EUID -ne 0 ]]; then fail "Run as root: sudo bash $0"; fi; }

check_os() {
    if grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
        ok "OS check passed"
    else
        warn "Designed for Ubuntu/Debian — proceed at your own risk"
    fi
}

check_ram() {
    local ram_gb
    ram_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    if (( ram_gb < 6 )); then
        warn "Only ${ram_gb}GB RAM — TheHive recommends at least 8GB"
    else
        ok "RAM check passed (${ram_gb}GB)"
    fi
}

# ── CONFIG PROMPTS ────────────────────────────────────────────────────────────

collect_config() {
    section "⚙  Configuration"
    echo -e "  ${DIM}Press Enter to accept the default shown in brackets.${RESET}"
    divider

    echo -e "\n  ${BOLD}${CYAN}[ Cassandra ]${RESET}"
    prompt_input "Cassandra keyspace name"            "thehive"    CASSANDRA_KEYSPACE
    prompt_input "Cassandra superuser username"       "cassandra"  CASSANDRA_USER
    prompt_input "Cassandra superuser password"       "cassandra"  CASSANDRA_PASS secret

    echo -e "\n  ${BOLD}${CYAN}[ Elasticsearch ]${RESET}"
    prompt_input "Elasticsearch cluster name"         "thehive"    ES_CLUSTER_NAME
    prompt_input "Elasticsearch HTTP port"            "9200"       ES_PORT
    prompt_input "Elasticsearch heap size (e.g. 3g)" "3g"         ES_HEAP

    echo -e "\n  ${BOLD}${CYAN}[ TheHive ]${RESET}"
    echo ""
    echo -e "  ${MAGENTA}┌─ ${WHITE}TheHive play.http.secret.key${RESET}"
    echo -e "  ${DIM}     Leave blank to auto-generate${RESET}"
    echo -ne "  ${MAGENTA}└─▶ ${RESET}"
    read -r THEHIVE_SECRET_KEY
    if [[ -z "$THEHIVE_SECRET_KEY" ]]; then
        THEHIVE_SECRET_KEY="$(openssl rand -base64 48 | tr -d '/+=' | head -c 64)"
        ok "Auto-generated secret key"
    fi

    echo -e "\n  ${BOLD}${CYAN}[ System ]${RESET}"
    prompt_yn "Wipe existing Cassandra + Elasticsearch data?" "y" WIPE_DATA
    if [[ "$WIPE_DATA" == "y" ]]; then warn "Existing data will be deleted!"; fi
    prompt_yn "Enable all services on boot?"                  "y" ENABLE_ON_BOOT

    section "📋 Installation Summary"
    echo ""
    summary_line "Cassandra keyspace"     "$CASSANDRA_KEYSPACE"
    summary_line "Cassandra user"         "$CASSANDRA_USER"
    summary_line "Elasticsearch cluster"  "$ES_CLUSTER_NAME"
    summary_line "Elasticsearch port"     "$ES_PORT"
    summary_line "Elasticsearch heap"     "$ES_HEAP"
    summary_line "TheHive secret key"     "${THEHIVE_SECRET_KEY:0:16}…"
    summary_line "Wipe existing data"     "$([ "$WIPE_DATA" == "y" ] && echo "Yes" || echo "No")"
    summary_line "Enable on boot"         "$([ "$ENABLE_ON_BOOT" == "y" ] && echo "Yes" || echo "No")"
    echo ""
    divider
    prompt_yn "Proceed with installation?" "y" PROCEED
    if [[ "$PROCEED" != "y" ]]; then echo -e "\n  ${WARN} Cancelled.\n"; exit 0; fi
    return 0
}

# ── INSTALL ───────────────────────────────────────────────────────────────────

install_base_packages() {
    section "📦 Base Packages"
    run_step "Updating package lists" apt-get update -qq
    run_step "Installing dependencies" apt-get install -y -qq \
        wget curl gnupg coreutils apt-transport-https git ca-certificates \
        ca-certificates-java software-properties-common python3-pip \
        lsb-release unzip
    ok "Base packages ready"
}

install_java() {
    section "☕ Java (Amazon Corretto 11)"
    run_step "Importing Corretto GPG key" bash -c \
        'wget -qO- https://apt.corretto.aws/corretto.key | gpg --dearmor -o /usr/share/keyrings/corretto.gpg'
    run_step "Adding Corretto repository" bash -c \
        'echo "deb [signed-by=/usr/share/keyrings/corretto.gpg] https://apt.corretto.aws stable main" > /etc/apt/sources.list.d/corretto.sources.list'
    run_step "Updating package lists" apt-get update -qq
    run_step "Installing Amazon Corretto 11" apt-get install -y -qq java-common java-11-amazon-corretto-jdk
    if ! grep -q "JAVA_HOME" /etc/environment; then echo 'JAVA_HOME="/usr/lib/jvm/java-11-amazon-corretto"' >> /etc/environment; fi
    export JAVA_HOME="/usr/lib/jvm/java-11-amazon-corretto"
    ok "Java installed"
}

install_python39() {
    section "🐍 Python 3.9 (for cqlsh)"
    run_step "Adding deadsnakes PPA" add-apt-repository -y ppa:deadsnakes/ppa
    run_step "Updating package lists" apt-get update -qq
    run_step "Installing Python 3.9" apt-get install -y -qq python3.9 python3.9-distutils
    run_step "Installing pip for Python 3.9" bash -c \
        'curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && python3.9 /tmp/get-pip.py --break-system-packages --ignore-installed'
    run_step "Installing six" python3.9 -m pip install -q six --break-system-packages
    ok "Python 3.9 ready"
}

install_cassandra() {
    section "🗄  Apache Cassandra"
    run_step "Importing Cassandra GPG key" bash -c \
        'wget -qO- https://downloads.apache.org/cassandra/KEYS | gpg --dearmor -o /usr/share/keyrings/cassandra-archive.gpg'
    run_step "Adding Cassandra repository" bash -c \
        'echo "deb [signed-by=/usr/share/keyrings/cassandra-archive.gpg] https://debian.cassandra.apache.org 41x main" > /etc/apt/sources.list.d/cassandra.sources.list'
    run_step "Updating package lists" apt-get update -qq
    run_step "Installing Cassandra" apt-get install -y -qq cassandra

    if [[ "$WIPE_DATA" == "y" ]]; then
        run_step "Stopping Cassandra"    systemctl stop cassandra || true
        run_step "Wiping Cassandra data" bash -c 'rm -rf /var/lib/cassandra/*'
    fi

    run_step "Setting data dir ownership" chown -R cassandra:cassandra /var/lib/cassandra
    run_step "Starting Cassandra"         systemctl start cassandra
    if [[ "$ENABLE_ON_BOOT" == "y" ]]; then run_step "Enabling Cassandra on boot" systemctl enable cassandra; fi

    step "Waiting for Cassandra to accept connections..."
    for i in {1..12}; do
        if ss -tlnp 2>/dev/null | grep -q ':9042 '; then
            ok "Cassandra is up"; break
        fi
        echo -ne "    ${DIM}attempt ${i}/12...${RESET}\r"
        sleep 5
    done
    echo ""

    step "Creating keyspace: ${CASSANDRA_KEYSPACE}"
    if CQLSH_PYTHON=/usr/bin/python3.9 cqlsh 127.0.0.1 9042 \
        -u "${CASSANDRA_USER}" -p "${CASSANDRA_PASS}" -e \
        "CREATE KEYSPACE IF NOT EXISTS ${CASSANDRA_KEYSPACE} WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};" \
        > /tmp/thehive_install.log 2>&1; then
        ok "Keyspace '${CASSANDRA_KEYSPACE}' created"
    else
        warn "Could not create keyspace — check /tmp/thehive_install.log"
    fi
}

install_elasticsearch() {
    section "🔍 Elasticsearch 8.x"
    run_step "Importing Elasticsearch GPG key" bash -c \
        'wget -qO- https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg'
    run_step "Installing apt-transport-https" apt-get install -y -qq apt-transport-https
    run_step "Adding Elasticsearch repository" bash -c \
        'echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list'
    run_step "Updating package lists" apt-get update -qq
    run_step "Installing Elasticsearch" apt-get install -y -qq elasticsearch

    step "Configuring elasticsearch.yml (cluster.name + disable xpack security)"
    # Set cluster.name
    sed -i "s/^#\?cluster\.name:.*/cluster.name: ${ES_CLUSTER_NAME}/" \
        /etc/elasticsearch/elasticsearch.yml
    # Hardcode xpack.security.enabled: false (required for ES 8 to start without TLS)
    if grep -q "^xpack.security.enabled" /etc/elasticsearch/elasticsearch.yml; then
        sed -i "s/^xpack\.security\.enabled:.*/xpack.security.enabled: false/" \
            /etc/elasticsearch/elasticsearch.yml
    else
        echo "xpack.security.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    fi
    ok "elasticsearch.yml configured"

    step "Writing JVM options"
    mkdir -p /etc/elasticsearch/jvm.options.d
    printf -- '-Dlog4j2.formatMsgNoLookups=true\n-Xms%s\n-Xmx%s\n' \
        "${ES_HEAP}" "${ES_HEAP}" \
        > /etc/elasticsearch/jvm.options.d/jvm.options
    ok "JVM options written (heap: ${ES_HEAP})"

    if [[ "$WIPE_DATA" == "y" ]]; then
        run_step "Stopping Elasticsearch"    systemctl stop elasticsearch || true
        run_step "Wiping Elasticsearch data" bash -c 'rm -rf /var/lib/elasticsearch/*'
    fi

    run_step "Starting Elasticsearch"        systemctl start elasticsearch
    if [[ "$ENABLE_ON_BOOT" == "y" ]]; then run_step "Enabling Elasticsearch on boot" systemctl enable elasticsearch; fi

    step "Waiting for Elasticsearch..."
    for i in {1..12}; do
        if curl -s "http://127.0.0.1:${ES_PORT}/_cluster/health" 2>/dev/null | grep -q '"status"'; then
            ok "Elasticsearch is up on port ${ES_PORT}"; break
        fi
        echo -ne "    ${DIM}attempt ${i}/12...${RESET}\r"
        sleep 5
    done
    echo ""
}

install_thehive() {
    section "🐝 TheHive 5"
    local deb_file="/tmp/thehive_5.6.0-1_all.deb"
    run_step "Downloading TheHive 5.6.0" bash -c \
        "wget -qO '${deb_file}' 'https://thehive.download.strangebee.com/5.6/deb/thehive_5.6.0-1_all.deb'"
    run_step "Installing TheHive" apt-get install -y -qq "${deb_file}"

    step "Writing play.http.secret.key into application.conf"
    if grep -q "play.http.secret.key" /etc/thehive/application.conf 2>/dev/null; then
        sed -i "s|play\.http\.secret\.key=.*|play.http.secret.key=\"${THEHIVE_SECRET_KEY}\"|" \
            /etc/thehive/application.conf
    else
        echo "play.http.secret.key=\"${THEHIVE_SECRET_KEY}\"" >> /etc/thehive/application.conf
    fi
    ok "Secret key written"

    run_step "Starting TheHive"  systemctl start thehive
    if [[ "$ENABLE_ON_BOOT" == "y" ]]; then run_step "Enabling TheHive on boot" systemctl enable thehive; fi
    run_step "Checking status"   systemctl status thehive --no-pager
}

# ── FINAL REPORT ──────────────────────────────────────────────────────────────

final_report() {
    section "✅ Installation Complete"

    color_status() {
        [[ "$1" == "active" ]] \
            && echo -e "${GREEN}● active${RESET}" \
            || echo -e "${RED}● ${1}${RESET}"
    }

    local cs es th
    cs=$(systemctl is-active cassandra     2>/dev/null || echo "unknown")
    es=$(systemctl is-active elasticsearch 2>/dev/null || echo "unknown")
    th=$(systemctl is-active thehive       2>/dev/null || echo "unknown")

    echo ""
    echo -e "  ${BOLD}Service Status${RESET}"
    printf "  %-20s %s\n" "Cassandra"      "$(color_status "$cs")"
    printf "  %-20s %s\n" "Elasticsearch"  "$(color_status "$es")"
    printf "  %-20s %s\n" "TheHive"        "$(color_status "$th")"
    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}Access TheHive at:${RESET}"
    echo -e "  ${CYAN}  http://$(hostname -I | awk '{print $1}'):9000${RESET}"
    echo ""
    echo -e "  ${BOLD}Default login:${RESET}  ${DIM}admin@thehive.local / secret${RESET}"
    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}Useful commands:${RESET}"
    echo -e "  ${DIM}  Cassandra logs  :${RESET}  journalctl -u cassandra -f"
    echo -e "  ${DIM}  ES logs         :${RESET}  journalctl -u elasticsearch -f"
    echo -e "  ${DIM}  TheHive logs    :${RESET}  journalctl -u thehive -f"
    echo -e "  ${DIM}  cqlsh           :${RESET}  CQLSH_PYTHON=/usr/bin/python3.9 cqlsh 127.0.0.1 9042 -u ${CASSANDRA_USER} -p <pass>"
    echo -e "  ${DIM}  ES health       :${RESET}  curl http://127.0.0.1:${ES_PORT}/_cluster/health"
    echo ""
    echo -e "  ${BOLD}${GREEN}Happy hunting! 🐝${RESET}"
    echo ""
}

# ── ENTRYPOINT ────────────────────────────────────────────────────────────────

main() {
    banner
    check_root
    section "🔎 Pre-flight Checks"
    check_os
    check_ram
    collect_config
    install_base_packages
    install_java
    install_python39
    install_cassandra
    install_elasticsearch
    install_thehive
    final_report
}

main "$@"