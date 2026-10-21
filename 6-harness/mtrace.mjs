// Call tracing for mcompare.mjs --trace FROM,TO,LABEL[+LABEL...][,EXTRA+...]:
// at each entry of a LABEL during main-loop iterations FROM..TO, log the
// label, its caller, A, X, Y, C, RAND and the EXTRA variables (NAME or
// NAME+offset), so that two runs' traces can be diffed to find where they part.
import { mapAt } from "./mlib.mjs";
export function makeTracer(spec, sy, out) {
    const [from, to, labels, extra] = spec.split(",");
    const labs = Object.entries(sy).filter(([k, v]) => v >= 0x100).sort((a, b) => a[1] - b[1]);
    const banks = sy.__bank;
    const near = (a, rs) => {
        let r = null;
        for (const [k, v] of labs) {
            if (v > a) break;
            if (a >= 0x8000 && a < 0xc000) { const b = banks[k]; if (b === undefined || mapAt(b, v) !== mapAt(rs, a)) continue; }
            r = k + "+" + (a - v);
        }
        return r;
    };
    const watch = new Map(labels.split("+").map(n => [sy[n], n]));
    const ex = (extra || "").split("+").filter(Boolean).map(n => { const [b, o] = n.split("~"); return [n, sy[b] + (+o || 0)]; });
    let inst = false, it = 0;
    return (i, s, res) => {
        it = i;
        if (inst) return;
        inst = true;
        const cpu = res.cpu;
        cpu.debugInstruction.add(pc => {
            if (it < +from || it > +to || !watch.has(pc)) return false;
            const n = watch.get(pc);
            if (banks[n] !== undefined && mapAt(banks[n], pc) !== mapAt(cpu.romsel, pc)) return false;
            const ret = (cpu.ramRomOs[0x101 + cpu.s] | cpu.ramRomOs[0x102 + cpu.s] << 8) - 2;
            const r = a => cpu.ramRomOs[a].toString(16).padStart(2, "0");
            out.push(`${it} ${n} from ${near(ret, cpu.romsel)} A=${cpu.a.toString(16)} X=${cpu.x.toString(16)} Y=${cpu.y.toString(16)} C=${cpu.p.c ? 1 : 0} RAND=${r(2)}${r(3)}${r(4)}${r(5)} ${ex.map(([n, a]) => n + "=" + r(a)).join(" ")}`);
            return false;
        });
    };
}
