import Foundation

/// The upload page served at `/`. It is deliberately self-contained: no CDN,
/// no fonts, no analytics, and no PIN or URL embedded in the markup.
public enum WiFiUploadPage {
    public static let html: String = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="referrer" content="no-referrer">
<meta name="color-scheme" content="light dark">
<title>LocalPod Wi-Fi Upload</title>
<style>
  :root {
    --bg: #f3f5f8;
    --card: #ffffff;
    --text: #14202e;
    --muted: #5c6b7a;
    --line: #dbe2ea;
    --accent: #0a67c2;
    --accent-strong: #08529b;
    --accent-soft: #e7f1fb;
    --success: #177245;
    --success-soft: #e6f5ec;
    --danger: #b3261e;
    --danger-soft: #fbeae8;
    --warning: #8a5a00;
    --warning-soft: #fdf3df;
    --shadow: 0 18px 44px rgba(20, 32, 46, 0.10);
    --radius: 18px;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0d131b;
      --card: #151e29;
      --text: #edf3f9;
      --muted: #9babbd;
      --line: #2a3746;
      --accent: #6cb4ff;
      --accent-strong: #8fc6ff;
      --accent-soft: #1a2c40;
      --success: #67d79b;
      --success-soft: #14301f;
      --danger: #ff9a92;
      --danger-soft: #3a1b19;
      --warning: #f0be62;
      --warning-soft: #342711;
      --shadow: 0 18px 44px rgba(0, 0, 0, 0.35);
    }
  }
  * { box-sizing: border-box; }
  html, body { min-height: 100%; }
  body {
    margin: 0;
    background:
      radial-gradient(1200px 600px at 110% -10%, var(--accent-soft), transparent 60%),
      var(--bg);
    color: var(--text);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI",
          "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .shell {
    width: min(760px, 100% - 32px);
    margin: 0 auto;
    padding: max(28px, env(safe-area-inset-top)) 0 48px;
  }
  .brand {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 22px;
  }
  .brand-left { display: flex; align-items: center; gap: 12px; }
  .logo {
    width: 42px; height: 42px; border-radius: 13px;
    background: linear-gradient(145deg, var(--accent), var(--accent-strong));
    display: grid; place-items: center; color: #fff; font-weight: 700;
    box-shadow: 0 8px 20px rgba(10, 103, 194, 0.30);
    flex: none;
  }
  .logo svg { width: 22px; height: 22px; display: block; }
  .brand h1 { font-size: 19px; line-height: 1.2; margin: 0; letter-spacing: -0.01em; }
  .brand p { margin: 3px 0 0; color: var(--muted); font-size: 12.5px; }
  .lang-btn {
    border: 1px solid var(--line); color: var(--muted); background: transparent;
    border-radius: 999px; padding: 7px 12px; font: inherit; font-size: 12.5px;
    cursor: pointer; white-space: nowrap;
  }
  .lang-btn:hover { border-color: var(--accent); color: var(--accent); }
  .card {
    background: var(--card);
    border: 1px solid var(--line);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    padding: clamp(20px, 4vw, 30px);
  }
  .hidden { display: none !important; }
  .eyebrow {
    color: var(--accent); font-size: 12px; font-weight: 650;
    letter-spacing: 0.08em; text-transform: uppercase; margin: 0 0 8px;
  }
  h2 { margin: 0 0 8px; font-size: clamp(22px, 4vw, 27px); line-height: 1.2; letter-spacing: -0.02em; }
  .sub { color: var(--muted); margin: 0 0 24px; font-size: 14px; }
  label.field { display: block; font-weight: 600; font-size: 13px; margin: 0 0 8px; }
  .pin-row { display: flex; gap: 10px; }
  input.pin {
    flex: 1; min-width: 0; font: inherit; font-size: 24px; letter-spacing: 0.32em;
    padding: 13px 16px; border-radius: 13px; border: 1px solid var(--line);
    background: var(--bg); color: var(--text); outline: none;
  }
  input.pin:focus { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .btn {
    appearance: none; border: 0; border-radius: 12px; padding: 12px 18px;
    font: inherit; font-weight: 650; cursor: pointer; white-space: nowrap;
    transition: transform 0.12s ease, background 0.12s ease, opacity 0.12s ease;
  }
  .btn:active:not(:disabled) { transform: scale(0.98); }
  .btn:disabled { opacity: 0.45; cursor: not-allowed; }
  .btn-primary { background: var(--accent); color: #fff; }
  @media (prefers-color-scheme: dark) { .btn-primary { color: #08121d; } }
  .btn-primary:hover:not(:disabled) { background: var(--accent-strong); }
  .btn-secondary { background: var(--accent-soft); color: var(--accent); }
  .btn-ghost { background: transparent; color: var(--muted); border: 1px solid var(--line); }
  .btn-danger { background: var(--danger-soft); color: var(--danger); }
  .fine { color: var(--muted); font-size: 12.5px; margin-top: 12px; }
  .message { margin-top: 14px; border-radius: 12px; padding: 11px 14px; font-size: 13.5px; }
  .message.error { background: var(--danger-soft); color: var(--danger); }
  .message.warn { background: var(--warning-soft); color: var(--warning); }
  .message.ok { background: var(--success-soft); color: var(--success); }
  .warnings { margin: 22px 0 0; padding: 0; list-style: none; display: grid; gap: 9px; }
  .warnings li {
    display: flex; gap: 10px; align-items: flex-start; color: var(--muted);
    font-size: 13px; background: var(--bg); border: 1px solid var(--line);
    border-radius: 12px; padding: 10px 13px;
  }
  .warnings svg { flex: none; width: 16px; height: 16px; margin-top: 1px; color: var(--warning); }
  .uploader-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 14px; flex-wrap: wrap; }
  .pin-chip {
    display: inline-flex; align-items: center; gap: 8px; border: 1px solid var(--line);
    border-radius: 999px; padding: 6px 7px 6px 12px; color: var(--muted); font-size: 12.5px;
  }
  .pin-chip button {
    border: 0; background: var(--accent-soft); color: var(--accent); border-radius: 999px;
    padding: 5px 10px; font: inherit; font-size: 12px; cursor: pointer;
  }
  .dropzone {
    margin-top: 22px; border: 1.5px dashed var(--line); border-radius: 16px;
    padding: 28px 18px; text-align: center; background: var(--bg);
    transition: border-color 0.15s ease, background 0.15s ease;
  }
  .dropzone.dragging { border-color: var(--accent); background: var(--accent-soft); }
  .dropzone svg { width: 34px; height: 34px; color: var(--accent); display: block; margin: 0 auto 10px; }
  .dropzone strong { display: block; font-size: 15px; margin-bottom: 4px; }
  .dropzone span { color: var(--muted); font-size: 13px; }
  .picker-row { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; margin-top: 16px; }
  .selection { margin-top: 22px; }
  .selection-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
  .selection-head .summary { color: var(--muted); font-size: 13px; }
  .selection-head .summary strong { color: var(--text); }
  .file-list {
    margin: 12px 0 0; padding: 0; list-style: none; max-height: 260px; overflow: auto;
    border: 1px solid var(--line); border-radius: 13px; background: var(--bg);
  }
  .file-list li {
    display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 6px 12px;
    padding: 9px 13px; border-bottom: 1px solid var(--line); font-size: 12.5px;
  }
  .file-list li:last-child { border-bottom: 0; }
  .file-name { overflow-wrap: anywhere; }
  .file-meta { color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
  .file-error { grid-column: 1 / -1; color: var(--danger); font-size: 12px; overflow-wrap: anywhere; }
  .status-done { color: var(--success); }
  .status-failed { color: var(--danger); }
  .status-active { color: var(--accent); }
  .progress-wrap { margin-top: 18px; }
  .progress-top { display: flex; justify-content: space-between; color: var(--muted); font-size: 12.5px; margin-bottom: 7px; }
  .bar { height: 9px; border-radius: 999px; background: var(--line); overflow: hidden; }
  .bar > div { height: 100%; width: 0%; border-radius: inherit; background: linear-gradient(90deg, var(--accent), var(--accent-strong)); transition: width 0.18s ease; }
  .actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 20px; }
  .success-panel { text-align: center; padding: 10px 0 4px; }
  .success-icon {
    width: 58px; height: 58px; border-radius: 50%; margin: 0 auto 16px;
    display: grid; place-items: center; background: var(--success-soft); color: var(--success);
  }
  .success-icon svg { width: 30px; height: 30px; }
  .success-panel h2 { font-size: 24px; }
  .success-panel p { color: var(--muted); margin: 4px auto 20px; max-width: 30em; }
  .footer { text-align: center; color: var(--muted); font-size: 11.5px; margin-top: 18px; }
  @media (max-width: 480px) {
    .shell { width: min(100% - 22px, 760px); }
    .pin-row { flex-direction: column; }
    .pin-row .btn { width: 100%; }
    .brand h1 { font-size: 17px; }
  }
</style>
</head>
<body>
<div class="shell">
  <header class="brand">
    <div class="brand-left">
      <div class="logo" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M4 14v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4"/>
          <path d="M12 3v11"/><path d="m8 10 4 4 4-4"/>
        </svg>
      </div>
      <div>
        <h1>LocalPod</h1>
        <p data-i18n="brandSub">Wi-Fi Upload</p>
      </div>
    </div>
    <button class="lang-btn" id="langToggle" type="button">中文</button>
  </header>

  <main class="card">
    <!-- PIN gate -->
    <section id="gate">
      <p class="eyebrow" data-i18n="gateEyebrow">Private connection</p>
      <h2 data-i18n="gateTitle">Enter the PIN from LocalPod</h2>
      <p class="sub" data-i18n="gateSub">The PIN is shown on the LocalPod screen. Your files stay on this local network.</p>
      <label class="field" for="pinInput" data-i18n="pinLabel">PIN</label>
      <div class="pin-row">
        <input class="pin" id="pinInput" type="password" inputmode="numeric" autocomplete="one-time-code"
               spellcheck="false" autocapitalize="off" maxlength="12" placeholder="••••••" aria-describedby="gateMessage">
        <button class="btn btn-primary" id="connectBtn" type="button" data-i18n="connect">Connect</button>
      </div>
      <div class="message error hidden" id="gateMessage" role="alert"></div>
      <ul class="warnings">
        <li>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 2 2 22h20L12 2Z"/><path d="M12 9v5"/><path d="M12 18h.01"/></svg>
          <span data-i18n="warnWifi">Connect your phone and computer to the same Wi-Fi network.</span>
        </li>
        <li>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="11" width="18" height="10" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          <span data-i18n="warnPublic">Do not use public or untrusted Wi-Fi.</span>
        </li>
        <li>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/></svg>
          <span data-i18n="warnForeground">Keep LocalPod open and in the foreground while uploading.</span>
        </li>
      </ul>
    </section>

    <!-- Uploader -->
    <section id="uploader" class="hidden">
      <div class="uploader-head">
        <div>
          <p class="eyebrow" data-i18n="uploadEyebrow">Connected</p>
          <h2 data-i18n="uploadTitle">Send files to LocalPod</h2>
          <p class="sub" id="uploadSub" data-i18n="uploadSub">Choose a folder or individual files. Folder structure is preserved.</p>
        </div>
        <div class="pin-chip">
          <span data-i18n="pinChip">PIN verified</span>
          <button id="changePinBtn" type="button" data-i18n="changePin">Change</button>
        </div>
      </div>

      <div class="dropzone" id="dropzone">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M4 14v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4"/>
          <path d="M12 16V4"/><path d="m7 9 5-5 5 5"/>
        </svg>
        <strong data-i18n="dropTitle">Drop files or folders here</strong>
        <span data-i18n="dropSub">or choose them below</span>
        <div class="picker-row">
          <button class="btn btn-secondary" id="pickFolderBtn" type="button" data-i18n="pickFolder">Choose folder</button>
          <button class="btn btn-ghost" id="pickFilesBtn" type="button" data-i18n="pickFiles">Choose files</button>
        </div>
        <input id="folderInput" class="hidden" type="file" webkitdirectory multiple>
        <input id="filesInput" class="hidden" type="file" multiple>
      </div>

      <div class="selection hidden" id="selection">
        <div class="selection-head">
          <div class="summary" id="selectionSummary"></div>
          <button class="btn btn-ghost" id="clearBtn" type="button" data-i18n="clear">Clear</button>
        </div>
        <ul class="file-list" id="fileList"></ul>
      </div>

      <div class="progress-wrap hidden" id="progressWrap">
        <div class="progress-top">
          <span id="progressLabel"></span>
          <span id="progressPercent">0%</span>
        </div>
        <div class="bar"><div id="progressBar"></div></div>
      </div>

      <div class="message error hidden" id="uploadMessage" role="alert"></div>
      <div class="message warn hidden" id="uploadWarning" role="status"></div>

      <div class="actions">
        <button class="btn btn-primary" id="startBtn" type="button" data-i18n="startUpload" disabled>Start upload</button>
        <button class="btn btn-danger hidden" id="cancelBtn" type="button" data-i18n="cancel">Cancel</button>
        <button class="btn btn-secondary hidden" id="retryBtn" type="button" data-i18n="retryFailed">Retry failed</button>
        <button class="btn btn-ghost hidden" id="addMoreBtn" type="button" data-i18n="uploadMore">Upload more</button>
      </div>
    </section>

    <!-- Success -->
    <section id="successPanel" class="success-panel hidden">
      <div class="success-icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m4 12.5 5 5L20 6.5"/></svg>
      </div>
      <h2 data-i18n="successTitle">Upload complete</h2>
      <p data-i18n="successBody">Upload complete. Return to LocalPod and keep it in the foreground.</p>
      <div class="actions" style="justify-content:center">
        <button class="btn btn-primary" id="moreBtn" type="button" data-i18n="uploadMore">Upload more</button>
      </div>
    </section>
  </main>

  <p class="footer" data-i18n="footer">Local network only · No cloud · No account</p>
</div>

<script>
(function () {
  "use strict";

  var copy = {
    zh: {
      brandSub: "Wi-Fi 上传",
      gateEyebrow: "私有连接",
      gateTitle: "输入 LocalPod 显示的 PIN",
      gateSub: "PIN 显示在 LocalPod 屏幕上。文件只在这台设备所在的局域网内传输。",
      pinLabel: "PIN",
      connect: "连接",
      connecting: "正在连接…",
      warnWifi: "请将手机和电脑连接到同一个 Wi-Fi 网络。",
      warnPublic: "请勿使用公共或不可信的 Wi-Fi。",
      warnForeground: "上传期间请让 LocalPod 保持打开并处于前台。",
      uploadEyebrow: "已连接",
      uploadTitle: "发送文件到 LocalPod",
      uploadSub: "可选择一个文件夹或若干文件。文件夹结构会保留。",
      pinChip: "PIN 已验证",
      changePin: "更换",
      dropTitle: "将文件或文件夹拖到这里",
      dropSub: "或使用下面的按钮选择",
      pickFolder: "选择文件夹",
      pickFiles: "选择文件",
      clear: "清除",
      startUpload: "开始上传",
      cancel: "取消",
      retryFailed: "重试失败项",
      uploadMore: "继续上传",
      successTitle: "上传完成",
      successBody: "上传完成，请回到 LocalPod 保持前台。",
      footer: "仅限局域网 · 无云端 · 无需账号",
      filesSelected: "已选择 {n} 个文件 · {size}",
      showingFirst: "（仅显示前 300 项）",
      fileProgress: "正在上传 {i}/{n}：{name}",
      overall: "总进度",
      waiting: "等待中",
      uploading: "上传中…",
      done: "已完成",
      failed: "失败",
      cancelled: "已取消",
      invalidPin: "PIN 不正确，请重试。",
      rateLimited: "尝试次数过多，请等待约 1 分钟后重试。",
      networkError: "无法连接 LocalPod。请确认使用同一 Wi-Fi，且 LocalPod 保持前台。",
      serverError: "服务器暂时不可用，请回到 LocalPod 重试。",
      pinChanged: "请输入新的 PIN。",
      noFiles: "请先选择文件。",
      cancelledNotice: "上传已取消。已完成的文件会保留。",
      someFailed: "部分文件上传失败。请检查后重试，失败项不会自动完成。",
      completedWithErrors: "有文件未能上传，因此没有完成本次批量。",
      completeFailed: "文件已上传，但无法完成本次批量：{msg}",
      uploadFailed: "上传失败（HTTP {status}）。",
      uploadFailedPath: "文件路径不受支持，请检查文件名。",
      uploadTooLarge: "文件或总量超出大小限制。",
      fileTooLarge: "文件过大。",
      totalTooLarge: "本次上传总量超出限制。",
      tooManyFiles: "文件数量超出限制。",
      verifyFailed: "PIN 验证失败（HTTP {status}）。",
      pinNeeded: "请输入 PIN。",
      clearDone: "已清除选择。",
      storageNote: "PIN 只保存在此标签页的会话存储中。"
    },
    en: {
      brandSub: "Wi-Fi Upload",
      gateEyebrow: "Private connection",
      gateTitle: "Enter the PIN from LocalPod",
      gateSub: "The PIN is shown on the LocalPod screen. Your files stay on this local network.",
      pinLabel: "PIN",
      connect: "Connect",
      connecting: "Connecting…",
      warnWifi: "Connect your phone and computer to the same Wi-Fi network.",
      warnPublic: "Do not use public or untrusted Wi-Fi.",
      warnForeground: "Keep LocalPod open and in the foreground while uploading.",
      uploadEyebrow: "Connected",
      uploadTitle: "Send files to LocalPod",
      uploadSub: "Choose a folder or individual files. Folder structure is preserved.",
      pinChip: "PIN verified",
      changePin: "Change",
      dropTitle: "Drop files or folders here",
      dropSub: "or choose them below",
      pickFolder: "Choose folder",
      pickFiles: "Choose files",
      clear: "Clear",
      startUpload: "Start upload",
      cancel: "Cancel",
      retryFailed: "Retry failed",
      uploadMore: "Upload more",
      successTitle: "Upload complete",
      successBody: "Upload complete. Return to LocalPod and keep it in the foreground.",
      footer: "Local network only · No cloud · No account",
      filesSelected: "{n} files selected · {size}",
      showingFirst: "(showing the first 300)",
      fileProgress: "Uploading {i}/{n}: {name}",
      overall: "Overall",
      waiting: "Waiting",
      uploading: "Uploading…",
      done: "Done",
      failed: "Failed",
      cancelled: "Cancelled",
      invalidPin: "Incorrect PIN. Please try again.",
      rateLimited: "Too many attempts. Wait about a minute and try again.",
      networkError: "Cannot reach LocalPod. Check that both devices use the same Wi-Fi and LocalPod stays open.",
      serverError: "The server is unavailable. Return to LocalPod and try again.",
      pinChanged: "Enter a new PIN.",
      noFiles: "Choose files first.",
      cancelledNotice: "Upload cancelled. Files already sent are kept.",
      someFailed: "Some files failed. Review them and retry; failed files are never auto-completed.",
      completedWithErrors: "Some files failed, so this batch was not completed.",
      completeFailed: "Files were uploaded, but the batch could not be completed: {msg}",
      uploadFailed: "Upload failed (HTTP {status}).",
      uploadFailedPath: "That file path is not supported. Check the file name.",
      uploadTooLarge: "The file or total size exceeds the limit.",
      fileTooLarge: "File is too large.",
      totalTooLarge: "This upload exceeds the total size limit.",
      tooManyFiles: "Too many files.",
      verifyFailed: "PIN verification failed (HTTP {status}).",
      pinNeeded: "Enter the PIN.",
      clearDone: "Selection cleared.",
      storageNote: "The PIN is kept only in this tab's session storage."
    }
  };

  var lang = String(navigator.language || navigator.userLanguage || "en").toLowerCase().indexOf("zh") === 0 ? "zh" : "en";
  var t = copy[lang];

  var gate = document.getElementById("gate");
  var uploader = document.getElementById("uploader");
  var successPanel = document.getElementById("successPanel");
  var pinInput = document.getElementById("pinInput");
  var connectBtn = document.getElementById("connectBtn");
  var gateMessage = document.getElementById("gateMessage");
  var changePinBtn = document.getElementById("changePinBtn");
  var dropzone = document.getElementById("dropzone");
  var folderInput = document.getElementById("folderInput");
  var filesInput = document.getElementById("filesInput");
  var selection = document.getElementById("selection");
  var selectionSummary = document.getElementById("selectionSummary");
  var fileList = document.getElementById("fileList");
  var progressWrap = document.getElementById("progressWrap");
  var progressLabel = document.getElementById("progressLabel");
  var progressPercent = document.getElementById("progressPercent");
  var progressBar = document.getElementById("progressBar");
  var uploadMessage = document.getElementById("uploadMessage");
  var uploadWarning = document.getElementById("uploadWarning");
  var startBtn = document.getElementById("startBtn");
  var cancelBtn = document.getElementById("cancelBtn");
  var retryBtn = document.getElementById("retryBtn");
  var addMoreBtn = document.getElementById("addMoreBtn");
  var clearBtn = document.getElementById("clearBtn");
  var moreBtn = document.getElementById("moreBtn");
  var langToggle = document.getElementById("langToggle");

  var storeKey = "localpod.wifi.pin";
  var pin = "";
  var entries = [];
  var entrySeq = 0;
  var uploading = false;
  var cancelled = false;
  var haltUploads = false;
  var currentXhr = null;
  var completedOnce = false;

  function $(id) { return document.getElementById(id); }
  function text(key) { return t[key] || key; }
  function fmt(key, values) {
    var out = text(key);
    Object.keys(values || {}).forEach(function (k) {
      out = out.replace("{" + k + "}", String(values[k]));
    });
    return out;
  }
  function formatBytes(bytes) {
    if (!bytes) return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var value = bytes;
    var i = 0;
    while (value >= 1024 && i < units.length - 1) { value /= 1024; i += 1; }
    var digits = value >= 100 || i === 0 ? 0 : value >= 10 ? 1 : 2;
    return value.toFixed(digits) + " " + units[i];
  }
  function normalizePath(path) {
    return String(path || "").replace(/\\/g, "/").split("/").filter(function (part) {
      return part.length > 0 && part !== ".";
    }).join("/").replace(/^\/+/, "");
  }
  function isJunkPath(path) {
    return String(path || "").split("/").some(function (part) {
      return part === ".DS_Store" || part === "Thumbs.db" ||
        part === "desktop.ini" || part === "__MACOSX" ||
        part.indexOf("._") === 0;
    });
  }
  function readStoredPin() {
    try { return sessionStorage.getItem(storeKey) || ""; } catch (e) { return ""; }
  }
  function storePin(value) {
    try {
      if (value) sessionStorage.setItem(storeKey, value);
      else sessionStorage.removeItem(storeKey);
    } catch (e) { /* private mode: keep in memory only */ }
  }
  function showMessage(element, kind, message) {
    if (!element) return;
    if (!message) {
      element.classList.add("hidden");
      element.textContent = "";
      return;
    }
    element.className = "message " + kind;
    element.textContent = message;
  }
  function clearMessages() {
    showMessage(gateMessage, "error", "");
    showMessage(uploadMessage, "error", "");
    showMessage(uploadWarning, "warn", "");
  }

  function applyCopy() {
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.querySelectorAll("[data-i18n]").forEach(function (node) {
      var key = node.getAttribute("data-i18n");
      if (t[key]) node.textContent = t[key];
    });
    langToggle.textContent = lang === "zh" ? "English" : "中文";
    pinInput.placeholder = "••••••";
    updateSelectionSummary();
    refreshButtons();
    if (uploading) {
      progressLabel.textContent = text("overall");
    }
  }

  function setGateVisible(visible) {
    gate.classList.toggle("hidden", !visible);
    uploader.classList.toggle("hidden", visible);
    if (visible) {
      successPanel.classList.add("hidden");
      pinInput.focus();
    }
  }

  function handleAuthFailure(status) {
    if (status === 429) {
      showMessage(gateMessage, "error", text("rateLimited"));
    } else {
      showMessage(gateMessage, "error", text("invalidPin"));
    }
    pin = "";
    storePin("");
    setGateVisible(true);
    pinInput.value = "";
    pinInput.focus();
    refreshButtons();
  }

  async function verifyPin(candidate) {
    if (!candidate) {
      showMessage(gateMessage, "error", text("pinNeeded"));
      return false;
    }
    connectBtn.disabled = true;
    connectBtn.textContent = text("connecting");
    showMessage(gateMessage, "error", "");
    try {
      var response = await fetch("/api/verify", {
        method: "GET",
        headers: { "X-LocalPod-Pin": candidate },
        cache: "no-store",
        credentials: "omit"
      });
      if (response.status === 204 || response.ok) {
        pin = candidate;
        storePin(candidate);
        setGateVisible(false);
        uploader.classList.remove("hidden");
        showMessage(uploadMessage, "error", "");
        refreshButtons();
        return true;
      }
      if (response.status === 429) {
        showMessage(gateMessage, "error", text("rateLimited"));
      } else if (response.status === 401) {
        showMessage(gateMessage, "error", text("invalidPin"));
      } else {
        showMessage(gateMessage, "error", fmt("verifyFailed", { status: response.status }));
      }
      return false;
    } catch (e) {
      showMessage(gateMessage, "error", text("networkError"));
      return false;
    } finally {
      connectBtn.disabled = false;
      connectBtn.textContent = text("connect");
      refreshButtons();
    }
  }

  function refreshButtons() {
    var hasEntries = entries.length > 0;
    var connected = !!pin;
    startBtn.disabled = uploading || !hasEntries || !connected;
    startBtn.classList.toggle("hidden", uploading);
    cancelBtn.classList.toggle("hidden", !uploading);
    retryBtn.classList.toggle("hidden", uploading || !hasEntries || !hasFailures());
    addMoreBtn.classList.toggle("hidden", uploading || !completedOnce);
    clearBtn.disabled = uploading;
    startBtn.textContent = text("startUpload");
    cancelBtn.textContent = text("cancel");
    retryBtn.textContent = text("retryFailed");
    addMoreBtn.textContent = text("uploadMore");
  }

  function hasFailures() {
    return entries.some(function (entry) {
      return entry.status === "failed" || entry.status === "cancelled";
    });
  }

  function updateSelectionSummary() {
    var total = entries.reduce(function (sum, entry) { return sum + entry.file.size; }, 0);
    selectionSummary.textContent = fmt("filesSelected", {
      n: entries.length,
      size: formatBytes(total)
    });
    selection.classList.toggle("hidden", entries.length === 0);
  }

  function statusLabel(entry) {
    if (entry.status === "done") return text("done");
    if (entry.status === "failed") return text("failed");
    if (entry.status === "cancelled") return text("cancelled");
    if (entry.status === "uploading") return text("uploading");
    return text("waiting");
  }

  function renderFileList() {
    fileList.textContent = "";
    var limit = Math.min(entries.length, 300);
    var fragment = document.createDocumentFragment();
    for (var i = 0; i < limit; i += 1) {
      var entry = entries[i];
      var li = document.createElement("li");
      var name = document.createElement("span");
      name.className = "file-name";
      name.textContent = entry.path || entry.file.name;
      var meta = document.createElement("span");
      meta.className = "file-meta status-" + entry.status;
      meta.textContent = entry.status === "done"
        ? formatBytes(entry.file.size) + " · " + statusLabel(entry)
        : formatBytes(entry.file.size) + " · " + statusLabel(entry);
      li.appendChild(name);
      li.appendChild(meta);
      if (entry.error) {
        var error = document.createElement("span");
        error.className = "file-error";
        error.textContent = entry.error;
        li.appendChild(error);
      }
      fragment.appendChild(li);
    }
    if (entries.length > limit) {
      var more = document.createElement("li");
      var note = document.createElement("span");
      note.className = "file-meta";
      note.textContent = text("showingFirst");
      more.appendChild(note);
      fragment.appendChild(more);
    }
    fileList.appendChild(fragment);
    updateSelectionSummary();
    refreshButtons();
  }

  function addEntries(items) {
    if (!items || !items.length) return;
    var nextSeq = entrySeq;
    items.forEach(function (item) {
      var path = normalizePath(item.path || item.file.name);
      if (!path || isJunkPath(path)) return;
      entries.push({
        seq: nextSeq++,
        file: item.file,
        path: path,
        status: "pending",
        error: ""
      });
    });
    entrySeq = nextSeq;
    showMessage(uploadWarning, "warn", "");
    completedOnce = false;
    successPanel.classList.add("hidden");
    renderFileList();
  }

  function filesFromInput(input) {
    var result = [];
    var files = input.files ? Array.prototype.slice.call(input.files) : [];
    files.forEach(function (file) {
      var relative = file.webkitRelativePath || file.name;
      result.push({ file: file, path: normalizePath(relative) });
    });
    input.value = "";
    return result;
  }

  async function walkEntry(entry, parentPrefix, output) {
    if (!entry) return;
    if (entry.isFile) {
      var file = await new Promise(function (resolve, reject) {
        entry.file(resolve, reject);
      });
      output.push({ file: file, path: normalizePath(parentPrefix + file.name) });
      return;
    }
    if (entry.isDirectory) {
      var reader = entry.createReader();
      var prefix = parentPrefix + entry.name + "/";
      while (true) {
        var batch = await new Promise(function (resolve, reject) {
          reader.readEntries(resolve, reject);
        });
        if (!batch || batch.length === 0) break;
        for (var i = 0; i < batch.length; i += 1) {
          await walkEntry(batch[i], prefix, output);
        }
      }
    }
  }

  async function addFromDataTransfer(dataTransfer) {
    var output = [];
    var items = dataTransfer.items ? Array.prototype.slice.call(dataTransfer.items) : [];
    var usedEntries = false;
    for (var i = 0; i < items.length; i += 1) {
      var item = items[i];
      if (item.kind !== "file") continue;
      var entry = item.webkitGetAsEntry ? item.webkitGetAsEntry() : null;
      if (entry) {
        usedEntries = true;
        try {
          await walkEntry(entry, "", output);
        } catch (e) { /* skip unreadable entry */ }
      }
    }
    if (!usedEntries) {
      var files = dataTransfer.files ? Array.prototype.slice.call(dataTransfer.files) : [];
      files.forEach(function (file) { output.push({ file: file, path: normalizePath(file.name) }); });
    }
    addEntries(output);
  }

  function setProgress(completedBytes, totalBytes, currentLoaded) {
    if (!totalBytes) {
      progressBar.style.width = "0%";
      progressPercent.textContent = "0%";
      return;
    }
    var loaded = completedBytes + (currentLoaded || 0);
    var ratio = Math.max(0, Math.min(1, loaded / totalBytes));
    var percent = Math.round(ratio * 100);
    progressBar.style.width = percent + "%";
    progressPercent.textContent = percent + "%";
  }

  function uploadFile(entry, overall) {
    return new Promise(function (resolve) {
      var xhr = new XMLHttpRequest();
      currentXhr = xhr;
      xhr.open("POST", "/api/upload", true);
      xhr.setRequestHeader("X-LocalPod-Pin", pin);
      xhr.setRequestHeader("X-LocalPod-Path", encodeURIComponent(entry.path));
      xhr.setRequestHeader("Content-Type", "application/octet-stream");
      xhr.responseType = "text";

      xhr.upload.onprogress = function (event) {
        if (!event.lengthComputable) return;
        entry.loaded = event.loaded;
        progressLabel.textContent = fmt("fileProgress", {
          i: overall.index,
          n: overall.total,
          name: entry.path
        });
        setProgress(overall.completedBytes, overall.totalBytes, event.loaded);
      };

      xhr.onload = function () {
        currentXhr = null;
        entry.loaded = entry.file.size;
        if (xhr.status >= 200 && xhr.status < 300) {
          entry.status = "done";
          entry.error = "";
          overall.completedBytes += entry.file.size;
          resolve(true);
          return;
        }
        entry.status = "failed";
        if (xhr.status === 401) {
          entry.error = text("invalidPin");
          haltUploads = true;
          handleAuthFailure(401);
        } else if (xhr.status === 429) {
          entry.error = text("rateLimited");
          haltUploads = true;
          handleAuthFailure(429);
        } else if (xhr.status === 400) {
          entry.error = text("uploadFailedPath");
        } else if (xhr.status === 413) {
          entry.error = text("uploadTooLarge");
        } else if (xhr.status === 503) {
          entry.error = text("serverError");
        } else {
          entry.error = fmt("uploadFailed", { status: xhr.status });
        }
        resolve(false);
      };

      xhr.onerror = function () {
        currentXhr = null;
        entry.status = "failed";
        entry.error = text("networkError");
        resolve(false);
      };

      xhr.onabort = function () {
        currentXhr = null;
        entry.status = "cancelled";
        entry.error = text("cancelledNotice");
        resolve(false);
      };

      xhr.send(entry.file);
    });
  }

  async function completeBatch() {
    try {
      var response = await fetch("/api/complete", {
        method: "POST",
        headers: {
          "X-LocalPod-Pin": pin,
          "Content-Type": "application/octet-stream"
        },
        body: new Blob([]),
        cache: "no-store",
        credentials: "omit"
      });
      if (response.ok) return true;
      if (response.status === 401) {
        handleAuthFailure(401);
        return false;
      }
      if (response.status === 429) {
        handleAuthFailure(429);
        return false;
      }
      var message = text("serverError");
      try {
        var parsed = await response.json();
        if (parsed && parsed.error) message = String(parsed.error);
      } catch (e) { /* use generic */ }
      showMessage(uploadWarning, "warn", fmt("completeFailed", { msg: message }));
      return false;
    } catch (e) {
      showMessage(uploadMessage, "error", text("networkError"));
      return false;
    }
  }

  async function runUpload(onlyFailed) {
    if (uploading) return;
    if (!pin) {
      setGateVisible(true);
      return;
    }
    var targets = entries.filter(function (entry) {
      if (onlyFailed) {
        // Pending entries can remain after a cancel, so include them too.
        return entry.status === "pending"
          || entry.status === "failed"
          || entry.status === "cancelled";
      }
      return entry.status === "pending" || entry.status === "failed" || entry.status === "cancelled";
    });
    if (targets.length === 0) {
      if (!onlyFailed && entries.length > 0) {
        var ok = await completeBatch();
        if (ok) showSuccess();
      }
      return;
    }

    uploading = true;
    cancelled = false;
    haltUploads = false;
    completedOnce = false;
    clearMessages();
    successPanel.classList.add("hidden");
    uploader.classList.remove("hidden");
    progressWrap.classList.remove("hidden");
    targets.forEach(function (entry) { entry.status = "pending"; entry.error = ""; entry.loaded = 0; });
    renderFileList();
    refreshButtons();

    var totalBytes = targets.reduce(function (sum, entry) { return sum + entry.file.size; }, 0);
    var overall = { total: targets.length, index: 0, completedBytes: 0, totalBytes: totalBytes };
    setProgress(0, totalBytes, 0);

    var failures = 0;
    for (var i = 0; i < targets.length; i += 1) {
      if (cancelled || haltUploads) break;
      var entry = targets[i];
      overall.index = i + 1;
      entry.status = "uploading";
      renderFileList();
      progressLabel.textContent = fmt("fileProgress", {
        i: overall.index,
        n: overall.total,
        name: entry.path
      });
      var success = await uploadFile(entry, overall);
      if (!success) {
        failures += 1;
        if (cancelled || haltUploads) break;
      }
      renderFileList();
    }

    uploading = false;
    currentXhr = null;
    refreshButtons();

    if (haltUploads) {
      progressWrap.classList.add("hidden");
      renderFileList();
      return;
    }

    if (cancelled) {
      showMessage(uploadWarning, "warn", text("cancelledNotice"));
      progressWrap.classList.add("hidden");
      return;
    }

    if (failures > 0) {
      showMessage(uploadMessage, "error", text("someFailed"));
      progressWrap.classList.add("hidden");
      renderFileList();
      return;
    }

    var completed = await completeBatch();
    if (!completed) {
      progressWrap.classList.add("hidden");
      renderFileList();
      return;
    }
    showSuccess();
  }

  function showSuccess() {
    progressWrap.classList.add("hidden");
    uploader.classList.add("hidden");
    gate.classList.add("hidden");
    successPanel.classList.remove("hidden");
    completedOnce = true;
    refreshButtons();
  }

  function resetForMore() {
    entries = [];
    completedOnce = false;
    uploadMessage.classList.add("hidden");
    uploadWarning.classList.add("hidden");
    successPanel.classList.add("hidden");
    uploader.classList.remove("hidden");
    selection.classList.add("hidden");
    fileList.textContent = "";
    progressWrap.classList.add("hidden");
    renderFileList();
    refreshButtons();
  }

  function connect() {
    var candidate = pinInput.value.replace(/\s+/g, "");
    verifyPin(candidate);
  }

  connectBtn.addEventListener("click", connect);
  pinInput.addEventListener("keydown", function (event) {
    if (event.key === "Enter") { event.preventDefault(); connect(); }
  });
  pinInput.addEventListener("input", function () {
    pinInput.value = pinInput.value.replace(/[^\d]/g, "");
  });

  changePinBtn.addEventListener("click", function () {
    pin = "";
    storePin("");
    pinInput.value = "";
    setGateVisible(true);
    showMessage(gateMessage, "error", text("pinChanged"));
    refreshButtons();
  });

  document.getElementById("pickFolderBtn").addEventListener("click", function () { folderInput.click(); });
  document.getElementById("pickFilesBtn").addEventListener("click", function () { filesInput.click(); });
  folderInput.addEventListener("change", function () { addEntries(filesFromInput(folderInput)); });
  filesInput.addEventListener("change", function () { addEntries(filesFromInput(filesInput)); });

  dropzone.addEventListener("click", function (event) {
    if (event.target.closest("button") || event.target.tagName === "INPUT") return;
    filesInput.click();
  });
  ["dragenter", "dragover"].forEach(function (name) {
    dropzone.addEventListener(name, function (event) {
      event.preventDefault();
      event.stopPropagation();
      dropzone.classList.add("dragging");
    });
  });
  ["dragleave", "dragend"].forEach(function (name) {
    dropzone.addEventListener(name, function (event) {
      event.preventDefault();
      event.stopPropagation();
      dropzone.classList.remove("dragging");
    });
  });
  dropzone.addEventListener("drop", function (event) {
    event.preventDefault();
    event.stopPropagation();
    dropzone.classList.remove("dragging");
    if (event.dataTransfer) addFromDataTransfer(event.dataTransfer);
  });
  window.addEventListener("dragover", function (event) { event.preventDefault(); });
  window.addEventListener("drop", function (event) { event.preventDefault(); });

  startBtn.addEventListener("click", function () { runUpload(false); });
  retryBtn.addEventListener("click", function () { runUpload(true); });
  cancelBtn.addEventListener("click", function () {
    cancelled = true;
    if (currentXhr) {
      try { currentXhr.abort(); } catch (e) { /* already finished */ }
    }
  });
  clearBtn.addEventListener("click", function () {
    if (uploading) return;
    entries = [];
    completedOnce = false;
    renderFileList();
    showMessage(uploadWarning, "warn", text("clearDone"));
  });
  addMoreBtn.addEventListener("click", resetForMore);
  moreBtn.addEventListener("click", resetForMore);

  langToggle.addEventListener("click", function () {
    lang = lang === "zh" ? "en" : "zh";
    t = copy[lang];
    showMessage(gateMessage, "error", "");
    showMessage(uploadMessage, "error", "");
    showMessage(uploadWarning, "warn", "");
    applyCopy();
    renderFileList();
  });

  applyCopy();
  refreshButtons();
  updateSelectionSummary();
  pin = readStoredPin();
  if (pin) {
    verifyPin(pin);
  } else {
    setGateVisible(true);
  }
})();
</script>
</body>
</html>
"""#
}
