// Command-line options for the harness and agentplay tools, parsed strictly.
//
// parseArgs(spec, argv = process.argv.slice(2), { positional = false } = {})
//   spec: { name: "value" | "flag" }. "--name value" (or "--name=value") for a value,
//   "--name" alone for a flag. Returns { name: value or true, _: [positionals] }.
// An option not in spec, a value option with no value, a flag given a value, or a
// stray positional argument is an error: the tool prints it and exits with status 2.
//
// (The tools used to skip anything they did not recognise. zsh does not split an
// unquoted $VAR, so C="--cand X --csyms Y"; replay.mjs $C passed one argument,
// "--cand X --csyms Y", which was skipped: the replay then ran the build named in the
// log's header, another worktree's, with no warning, and its findings looked like
// nondeterminism.)
export function parseArgs(spec, argv = process.argv.slice(2), { positional = false } = {}) {
    const out = { _: [] };
    const die = msg => { console.error(`${msg}\nknown options: ${Object.entries(spec).map(([k, t]) => t === "flag" ? `--${k}` : `--${k} V`).join(" ")}`); process.exit(2); };
    for (let i = 0; i < argv.length; i++) {
        const v = argv[i];
        if (!v.startsWith("--")) { if (positional) { out._.push(v); continue; } die(`unexpected argument ${JSON.stringify(v)}`); }
        const eq = v.indexOf("=");
        const name = eq > 0 ? v.slice(2, eq) : v.slice(2);
        const type = Object.hasOwn(spec, name) ? spec[name] : null;
        if (!type) die(`unknown option ${JSON.stringify(v)}${/\s/.test(v) ? " (one argument holding several: in zsh an unquoted $VAR is not split into words)" : ""}`);
        if (type === "flag") { if (eq > 0) die(`--${name} takes no value`); out[name] = true; continue; }
        if (eq > 0) { out[name] = v.slice(eq + 1); continue; }
        if (i + 1 >= argv.length || argv[i + 1].startsWith("--")) die(`--${name} needs a value`);
        out[name] = argv[++i];
    }
    return out;
}
