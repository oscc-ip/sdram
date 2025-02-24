let elements = document.querySelectorAll("#preamble");
let osdependent = document.querySelectorAll(".windows,.linux,.macos");
if (elements.length > 0 && osdependent.length > 0) {
    function setStore(cname, cvalue) {
        if (localStorage !== undefined) {
            localStorage.setItem(cname, cvalue);
        }
    }

    function getStore(cname) {
        if (localStorage !== undefined) {
            let item = localStorage.getItem(cname);
            if (item === null) {
                return undefined;
            }
            return item;
        }
        return undefined;
    }

    function osChanged(value) {
        setStore("os", value)
        document.head.querySelectorAll('[data-os-switcher]').forEach(e => e.remove())
        const style = document.createElement("style")
        style.setAttribute("data-os-switcher", "")
        let macos = false
        let windows = false
        let linux = false, content
        if (value !== 'unknown') {
            if (value === 'macos') {
                macos = true
            } else if (value === 'windows') {
                windows = true
            } else if (value === 'linux') {
                linux = true
            }
            content = `
            .macos,.windows,.linux { display: none }
            .macos::after {  content: ''; }
            .windows::after {  content: ''; } 
            .linux::after {  content: ''; }
            .windows.linux::after {  content: ''; } 
            .windows.mac::after {  content: ''; } 
            .linux.mac::after {  content: ''; }
            `
            if (macos === true) {
                content += ".macos { display: initial }"
            }
            if (windows === true) {
                content += `.windows { display: initial }`
            }
            if (linux === true) {
                content += `.linux { display: initial }`
            }
        } else {
            content = ``
        }
        style.textContent = content
        document.head.appendChild(style)
    }

    let h2 = elements[0]
    const newDiv = document.createElement("div");
    let os = getStore("os")
    if (os === undefined) {
        os = "unknown"
        let userAgent = navigator.userAgent
        if (userAgent !== undefined) {
            if (userAgent.indexOf("Win") !== -1) {
                os = "windows";
            }
            if (userAgent.indexOf("Mac") !== -1) {
                os = "macos";
            }
            if (userAgent.indexOf("X11") !== -1) {
                os = "linux";
            }
            if (userAgent.indexOf("Linux") !== -1) {
                os = "linux";
            }
        }
    }
    osChanged(os)
    newDiv.innerHTML = `
        <div class="sectionbody">
        <div class="paragraph">
        <label for="os">Choose the operating system to display the matching shortcuts:</label>
        
        <select name="os" id="os" onchange="osChanged(this.value)">
          <option value="unknown" ${ os === "unknown" ? "selected": ""}>Unknown</option>
          <option value="windows" ${ os === "windows" ? "selected": ""}>Windows</option>
          <option value="linux" ${ os === "linux" ? "selected": ""}>Linux</option>
          <option value="macos" ${ os === "macos" ? "selected": ""}>macOS</option>
        </select>
        </div>
        </div>
    `
    h2.appendChild(newDiv);
}
