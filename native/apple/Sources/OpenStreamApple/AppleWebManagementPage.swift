import Foundation

public enum AppleWebManagementPage {
    public static func setup(token: String, manifest: String = "", error: String? = nil) -> String {
        let feedback = error.map {
            "<p class=\"error\" role=\"alert\"><strong>Couldn’t add source.</strong> \(escape($0))</p>"
        } ?? ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <meta name="color-scheme" content="dark">
          <title>OpenStream Web Management</title>
          <style>\(styles)</style>
        </head>
        <body>
          <main>
            <header><span class="mark" aria-hidden="true"></span><span>OpenStream</span></header>
            <section>
              <p class="eyebrow">WEB MANAGEMENT</p>
              <h1>Add a source</h1>
              <form method="post" action="/openstream" autocomplete="off">
                <input type="hidden" name="token" value="\(escape(token))">
                <label for="manifest">Manifest URL</label>
                <input id="manifest" name="manifest" type="url" required inputmode="url"
                  placeholder="https://addon.example/manifest.json" value="\(escape(manifest))"
                  autocapitalize="none" autocomplete="url" spellcheck="false">
                \(feedback)
                <button type="submit">Add source</button>
              </form>
            </section>
          </main>
        </body>
        </html>
        """
    }

    public static func success(sourceName: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <meta name="color-scheme" content="dark">
          <title>Source added to OpenStream</title>
          <style>\(styles)</style>
        </head>
        <body>
          <main>
            <header><span class="mark" aria-hidden="true"></span><span>OpenStream</span></header>
            <section role="status">
              <div class="check" aria-hidden="true">✓</div>
              <p class="eyebrow">SOURCE CONNECTED</p>
              <h1>Source added</h1>
              <p class="success"><strong>\(escape(sourceName))</strong></p>
            </section>
          </main>
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let styles = """
    :root{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",sans-serif;color:#f5f5f7;background:#000}*{box-sizing:border-box}body{min-height:100vh;margin:0;padding:max(24px,env(safe-area-inset-top)) max(18px,env(safe-area-inset-right)) max(24px,env(safe-area-inset-bottom)) max(18px,env(safe-area-inset-left));display:grid;place-items:center;background:#000}main{width:min(100%,520px)}header{display:flex;align-items:center;gap:10px;margin:0 0 20px 2px;font-size:21px;font-weight:760;letter-spacing:-.035em}.mark{width:27px;height:27px;border:7px solid #f5f5f7;border-radius:8px;transform:rotate(45deg)}section{padding:clamp(22px,6vw,32px);border:1px solid #2c2c2e;border-radius:16px;background:#0c0c0d}.eyebrow{margin:0 0 8px;color:#98989d;font-size:11px;font-weight:750;letter-spacing:.14em}h1{margin:0 0 24px;font-size:clamp(28px,8vw,36px);line-height:1.08;letter-spacing:-.035em}form{display:grid;gap:10px}label{font-size:13px;font-weight:650}input{width:100%;min-height:50px;padding:13px 14px;border:1px solid #3a3a3c;border-radius:10px;background:#1c1c1e;color:#f5f5f7;font:inherit;outline:none}input::placeholder{color:#636366}input:focus{border-color:#f5f5f7;box-shadow:0 0 0 3px #ffffff20}.error{margin:2px 0 4px;padding:11px 12px;border:1px solid #6e2429;border-radius:9px;background:#260b0e;color:#ffb4b8;font-size:13px;line-height:1.4}.error strong{color:#fff}button{justify-self:start;min-height:44px;margin-top:6px;padding:10px 18px;border:0;border-radius:9px;background:#f5f5f7;color:#000;font:inherit;font-size:14px;font-weight:750;cursor:pointer}button:hover{background:#d1d1d6}button:focus-visible{outline:3px solid #f5f5f7;outline-offset:3px}.check{width:42px;height:42px;margin-bottom:18px;border:1px solid #f5f5f7;border-radius:50%;display:grid;place-items:center;font-size:23px;font-weight:800}.success{margin:0;color:#aeaeb2;font-size:15px}.success strong{color:#f5f5f7}@media(max-width:420px){body{padding:16px 13px}header{margin-bottom:15px}section{padding:22px 19px;border-radius:13px}}
    """
}
