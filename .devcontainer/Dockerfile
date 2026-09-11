# 健金術 Alchemy Workout —— Codespaces 開發環境
#
# **為什麼需要這個檔案**：這個專案釘死 Flutter 3.44.1（Dart 3.12.1），
# 而那個版本的 Dart VM 要求 macOS 14.0 以上。原本的開發機是 2017 年的
# MacBook Pro，硬體本身就不支援 macOS 14，所以在那台機器上永遠跑不起來。
# 見 PROGRESS.md 第 2 節。
#
# 版本**必須**是 3.44.1：PROGRESS.md 明確警告版本漂移會讓上千個測試一起紅。
# 要升版是獨立的決定，不可以因為這個檔案順手改掉。

FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Flutter 在 Linux 上跑 test / analyze 需要的東西。
# libglu1-mesa 是 flutter doctor 會抓的相依，少了它 doctor 會報警告。
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        curl git unzip xz-utils zip libglu1-mesa \
        chromium-browser \
        # tools/build_web.sh 會建一個 venv 裝 fonttools 做字型子集化。
        # Ubuntu 的 python3 不含 ensurepip，少了這個套件 venv 建不起來，
        # 而那支腳本是專案規定唯一可用的 Web 建置方式（CLAUDE.md 硬性規則 2）。
        python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Flutter 3.44.1 stable（釘死版本，不用 git clone 追分支）---
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}

RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.1-stable.tar.xz" \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    # Codespaces 裡容器是以 vscode 這個使用者跑的，SDK 目錄要給它寫權限，
    # 否則第一次 flutter 指令會因為建不了 cache 而失敗。
    && chown -R vscode:vscode ${FLUTTER_HOME}

# flutter test --platform chrome 要靠這個環境變數找瀏覽器。
# PROGRESS.md 記載有 17 個測試只在 Chrome 上跑。
ENV CHROME_EXECUTABLE=/usr/bin/chromium-browser

USER vscode

# 先把 SDK 暖起來，第一次開 Codespace 才不用等它自己下載。
# --no-analytics 避免第一次執行跳出同意提示卡住自動化流程。
RUN flutter config --no-analytics \
    && flutter precache --universal \
    && dart --version && flutter --version
