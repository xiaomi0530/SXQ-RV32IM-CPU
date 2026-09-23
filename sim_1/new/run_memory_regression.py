"""Run actual CPU RTL with variable-latency slave responses (no source edits).

python sim_1/new/run_memory_regression.py [--official]
Use --toolchain DIR when riscv-none-elf-gcc/objcopy are not on PATH.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'sources_1/new'
TESTS = ROOT / 'sim_1/new'
OUT = ROOT / 'build/memory_regression'


def run(command, cwd=OUT):
    result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(' '.join(map(str, command)) + '\n' + result.stdout + result.stderr)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--official', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    cc = shutil.which('riscv-none-elf-gcc') or shutil.which('riscv64-unknown-elf-gcc')
    if args.toolchain:
        cc = next(args.toolchain.glob('*gcc.exe'), None) or next(args.toolchain.glob('*gcc'), None)
    if not cc:
        candidates = list((Path.home()/'Documents').glob('xpack-riscv*/**/bin/riscv-none-elf-gcc.exe'))
        cc = candidates[0] if candidates else None
    if not cc:
        raise RuntimeError('RISC-V compiler missing; use --toolchain DIR')
    cc = str(cc)
    objcopy = Path(cc).with_name(Path(cc).name.replace('gcc', 'objcopy'))
    iverilog = shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'
    vvp = shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe'

    # Reroute only the three slave response wires in a disposable CPU copy.
    # Production request/hold/flush logic and native peripherals are unchanged.
    text = (SRC/'cpu.v').read_text(encoding='utf-8')
    additions = []
    for n in range(3):
        ack, data = f'bus_s{n}_ack', f'bus_s{n}_dat_i'
        text, hits = re.subn(r'\.bus_ack\s*\(\s*'+ack+r'\s*\)', f'.bus_ack(native_ack{n})', text)
        assert hits == 1
        text, hits = re.subn(r'\.r_data\s*\(\s*'+data+r'\s*\)', f'.r_data(native_data{n})', text)
        assert hits == 1
        additions.append(f'wire native_ack{n}; wire [31:0] native_data{n};\n'
                         f'response_delay delay{n}(clk,rst_n,native_ack{n},native_data{n},{ack},{data});')
    text = text.replace('endmodule', '\n'.join(additions)+'\nendmodule')
    (OUT/'cpu_delay_test.v').write_text(text, encoding='utf-8')
    sources = [p for p in SRC.glob('*.v') if p.name not in ('top.v', 'cpu.v')]
    run([iverilog, '-g2012', '-I', SRC, '-s', 'memory_regression_tb', '-o', OUT/'test.vvp',
         *sources, OUT/'cpu_delay_test.v', TESTS/'memory_regression_tb.v'])

    def assemble(source, includes=()):
        run([cc, '-march=rv32im', '-mabi=ilp32', '-nostdlib', '-mno-relax',
             *includes, '-T', ROOT/'benchmarks/RISCV-TEST/rv32i_official/link.ld',
             source, '-o', OUT/'program.elf'])
        run([objcopy, '-O', 'binary', '--remove-section=.tohost', OUT/'program.elf', OUT/'program.bin'])
        data = (OUT/'program.bin').read_bytes()
        if len(data) > 32768:
            raise RuntimeError('Program exceeds IMEM')
        data = data.ljust(32768, b'\0')
        (OUT/'imem.mem').write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n'
                                         for i in range(0, len(data), 4)))

    logs = []
    def simulate(label, *options):
        result = run([vvp, OUT/'test.vvp', *options])
        logs.append(label+'\n'+result)
        print(label+': '+result.splitlines()[0], flush=True)

    assemble(TESTS/'memory_regression.S')
    for delay in [0, 1, 3, 11, 50]:
        simulate(f'memory delay {delay}', f'+DELAY={delay}')
    simulate('reset while waiting', '+DELAY=11', '+RESET_WAIT=1')
    for name, body in {
        'unmapped': 'li t0,0x20000000; lw t1,0(t0)',
        'misaligned word': 'li t0,0x10000; lw t1,1(t0)',
        'misaligned half store': 'li t0,0x10000; sh t1,1(t0)',
        'IMEM write': 'sw t1,0(zero)',
        'MMIO alias': 'li t0,0xf0000100; lw t1,0(t0)',
    }.items():
        (OUT/'fault.S').write_text('.section .text.init\n.globl _start\n_start:\n'+body+'\n1: j 1b\n')
        assemble(OUT/'fault.S')
        simulate(name, '+FAULT=1', '+DELAY=3')

    if args.official:
        official = ROOT/'benchmarks/RISCV-TEST/rv32i_official'
        upstream = ROOT/'benchmarks/RISCV-TEST/riscv-tests/isa'
        tests = 'simple add addi sub and andi or ori xor xori sll slli srl srli sra srai slt slti sltu sltiu lui auipc jal jalr beq bne blt bge bltu bgeu lb lbu lh lhu lw sb sh sw'.split()
        tests += 'mul mulh mulhsu mulhu div divu rem remu'.split()
        for name in tests:
            family = 'rv32um' if name in 'mul mulh mulhsu mulhu div divu rem remu'.split() else 'rv32ui'
            assemble(upstream/family/(name+'.S'), ['-I', official, '-I', upstream/'macros/scalar'])
            for delay in [0, 7]:
                simulate(f'official {name} delay {delay}', f'+DELAY={delay}', '+OFFICIAL')
    (OUT/'results.log').write_text('\n'.join(logs), encoding='utf-8')
    print(f'PASS {len(logs)} cases; {OUT/"results.log"}')


if __name__ == '__main__':
    main()
