import Foundation

/// Shell-Befehle, die per `ssh … sh -s` über stdin auf dem Host ausgeführt werden.
/// Die Übergabe über stdin vermeidet jegliche Quoting-Probleme mit der Login-Shell des Hosts.
enum RemoteScripts {
    /// Ermittelt den Docker-Pfad in `$D` – auch wenn `docker` nicht im PATH einer Non-Login-Shell liegt.
    static let dockerLocator =
        #"D=$(command -v docker 2>/dev/null); [ -z "$D" ] && for p in /usr/local/bin/docker /usr/bin/docker /bin/docker; do [ -x "$p" ] && D="$p" && break; done"#

    /// Ein einziger Abfrage-Einzeiler. Abschnitte sind durch `@@MARKER`-Zeilen getrennt.
    static let status = [
        "export LC_ALL=C",
        #"PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin""#,
        "echo @@CPU; head -n1 /proc/stat; sleep 1; head -n1 /proc/stat",
        "echo @@NPROC; nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo",
        "echo @@LOAD; cat /proc/loadavg",
        "echo @@MEM; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo",
        "echo @@DISK; df -P -k / /volume1 /mnt 2>/dev/null",
        "echo @@UPTIME; cat /proc/uptime",
        dockerLocator,
        #"if [ -n "$D" ]; then echo @@DOCKER; "$D" ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}|{{.Label "com.docker.compose.project"}}' 2>&1; echo "@@DOCKERRC $?"; else echo @@NODOCKER; fi"#,
        "echo @@END"
    ].joined(separator: "; ") + "\n"

    /// Führt einen Docker-Unterbefehl aus. Exit-Code 127 signalisiert „Docker nicht gefunden“.
    static func docker(_ arguments: String) -> String {
        [
            #"PATH="$PATH:/usr/local/bin:/usr/bin:/bin""#,
            dockerLocator,
            #"if [ -z "$D" ]; then echo 'docker: command not found' >&2; exit 127; fi"#,
            #""$D" "# + arguments
        ].joined(separator: "; ") + "\n"
    }
}
