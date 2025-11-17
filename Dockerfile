FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    GOPATH=/root/go \
    GOBIN=/usr/local/bin \
    PATH="/opt/hexstrike-ai/venv/bin:/usr/local/bin:${PATH}" \
    GO111MODULE=on

RUN printf '%s\n' \
  'deb http://kali.download/kali kali-rolling main contrib non-free non-free-firmware' \
  > /etc/apt/sources.list

# ---- Base tools & libs -------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev build-essential pkg-config \
    git ca-certificates curl golang-go \
    libpcap-dev \
    # nmap masscan amass subfinder nuclei fierce dnsenum autorecon theharvester responder netexec \
    # gobuster feroxbuster dirsearch ffuf dirb nikto sqlmap wpscan arjun wafw00f parallel metasploit-framework \
    # SSH server
    openssh-server \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---- ParamSpider via APT (fallback pip) -------------------------------------
RUN (apt-get update && apt-get install -y --no-install-recommends paramspider && rm -rf /var/lib/apt/lists/*) || \
    (pip3 install --no-cache-dir paramspider)

# ---- Go-based tools ----------------------------------------------------------
RUN go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install -v github.com/projectdiscovery/katana/cmd/katana@latest && \
    go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest && \
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install -v github.com/tomnomnom/waybackurls@latest && \
    go install -v github.com/jaeles-project/gospider@latest && \
    go install -v github.com/tomnomnom/gf@latest && \
    go install -v github.com/tomnomnom/qsreplace@latest && \
    go install -v github.com/lc/gau/v2/cmd/gau@latest && \
    go install -v github.com/xm1k3/cent/v2@latest

# ---- Nuclei templates via cent ----------------------------------------------
ENV NUCLEI_TEMPLATES_PATH=/opt/hexstrike-ai/cent-nuclei-templates
RUN mkdir -p "${NUCLEI_TEMPLATES_PATH}" && cent -p "${NUCLEI_TEMPLATES_PATH}"

# ---- GF patterns -------------------------------------------------------------
RUN git clone --depth=1 https://github.com/1ndianl33t/Gf-Patterns /tmp/Gf-Patterns && \
    git clone --depth=1 https://github.com/dwisiswant0/gf-secrets /tmp/gf-secrets && \
    mkdir -p /root/.gf && \
    cp /tmp/Gf-Patterns/*.json /root/.gf/ && \
    cp /tmp/gf-secrets/.gf/*.json /root/.gf/ && \
    rm -rf /tmp/Gf-Patterns /tmp/gf-secrets

# ---- GNU parallel (auto agree cite) -----------------------------------------
RUN mkdir -p /root/.parallel && echo 'will cite' > /root/.parallel/will-cite

# ---- App code & Python venv --------------------------------------------------
WORKDIR /opt/hexstrike-ai
COPY . /opt/hexstrike-ai/

RUN python3 -m venv /opt/hexstrike-ai/venv && \
    pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt

# (opsional) inisialisasi lagi bila perlu
RUN cent -p "${NUCLEI_TEMPLATES_PATH}" && cent init || true

RUN cent -p "${NUCLEI_TEMPLATES_PATH}"

# ---- SSH: user non-root (opsional) + root pubkey ----------------------------
# Buat user non-root "app" (biarkan ada untuk opsi non-root)
RUN useradd -m -s /bin/bash app

# Folder runtime sshd
RUN mkdir -p /var/run/sshd

# Tambahkan kunci publik saat build (opsional, bisa juga di-mount saat run)
ARG SSH_PUBKEY=""
# Untuk user app
RUN mkdir -p /home/app/.ssh && \
    sh -c 'if [ -n "$SSH_PUBKEY" ]; then echo "$SSH_PUBKEY" > /home/app/.ssh/authorized_keys; fi' && \
    chown -R app:app /home/app/.ssh && \
    chmod 700 /home/app/.ssh && \
    [ ! -f /home/app/.ssh/authorized_keys ] || chmod 600 /home/app/.ssh/authorized_keys
# Untuk user root
RUN mkdir -p /root/.ssh && \
    sh -c 'if [ -n "$SSH_PUBKEY" ]; then echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys; fi' && \
    chown -R root:root /root/.ssh && \
    chmod 700 /root/.ssh && \
    [ ! -f /root/.ssh/authorized_keys ] || chmod 600 /root/.ssh/authorized_keys

# Hardening sshd_config (port 2222, pubkey only, root allowed via key)
RUN printf '%s\n' \
  'Port 2222' \
  'PermitRootLogin prohibit-password' \
  'PasswordAuthentication no' \
  'ChallengeResponseAuthentication no' \
  'UsePAM no' \
  'PubkeyAuthentication yes' \
  'AllowUsers root app' \
  'LoginGraceTime 10' \
  'MaxAuthTries 3' \
  'X11Forwarding no' \
  'UseDNS no' \
  >> /etc/ssh/sshd_config

# ---- App env -----------------------------------------------------------------
ENV HEXSTRIKE_PORT=8888
ENV HEXSTRIKE_URL_INTERNAL="http://127.0.0.1:8888"

# ---- Ports -------------------------------------------------------------------
EXPOSE 8888 2222

# ---- Entrypoint: start sshd + jalankan server Python ------------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
# Fix CRLF kalau file dibuat di Windows
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["python3", "/opt/hexstrike-ai/hexstrike_server.py", "--port", "8888"]
