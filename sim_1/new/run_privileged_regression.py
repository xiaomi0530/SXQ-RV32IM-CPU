"""Architectural CSR/trap/interrupt regression, using actual delayed CPU RTL."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'sources_1/new'
OUT=ROOT/'build/privileged_regression'

def run(args):
    p=subprocess.run(list(map(str,args)),cwd=OUT,capture_output=True,text=True,timeout=240)
    if p.returncode: raise RuntimeError(p.stdout+p.stderr)
    return p.stdout

def main():
    global OUT
    parser=argparse.ArgumentParser()
    parser.add_argument('--program',type=Path,default=ROOT/'sim_1/new/privileged_regression.S')
    parser.add_argument('--trace',action='store_true')
    parser.add_argument('--freertos',action='store_true',help='Build pinned upstream FreeRTOS and run preemptive tasks')
    args=parser.parse_args()
    if args.freertos: OUT=ROOT/'build/freertos_regression'
    OUT.mkdir(parents=True,exist_ok=True)
    cc=shutil.which('riscv-none-elf-gcc') or next((Path.home()/'Documents').glob('xpack-riscv*/**/bin/riscv-none-elf-gcc.exe'))
    cc=Path(cc)
    if args.freertos:
        kernel=ROOT/'build/privileged/FreeRTOS-Kernel'
        if not kernel.exists():
            run(['git','clone','--depth','1','--branch','V11.2.0','https://github.com/FreeRTOS/FreeRTOS-Kernel.git',kernel])
        revision=run(['git','-C',kernel,'rev-parse','HEAD']).strip()
        if revision!='0adc196d4bd52a2d91102b525b0aafc1e14a2386':
            raise RuntimeError('Unexpected FreeRTOS revision: '+revision)
        demo=ROOT/'sim_1/new/freertos'
        port=kernel/'portable/GCC/RISC-V'
        run([cc,'-march=rv32im_zicsr_zifencei','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin',
             '-fdata-sections','-ffunction-sections','-msmall-data-limit=0','-mno-relax','-nostdlib',
             '-Wl,--gc-sections','-Wl,-Map=program.map','-T',ROOT/'benchmarks/RISCV-TEST/rv32i_official/link.ld',
             '-I',demo,'-I',kernel/'include','-I',port,'-I',port/'chip_specific_extensions/RV32I_CLINT_no_extensions',
             demo/'start.S',demo/'main.c',kernel/'tasks.c',kernel/'list.c',kernel/'queue.c',port/'port.c',port/'portASM.S',
             '-lgcc','-o','program.elf'])
        print(run([cc.with_name(cc.name.replace('gcc','size')),'program.elf']),flush=True)
    else:
        run([cc,'-march=rv32im_zicsr_zifencei','-mabi=ilp32','-nostdlib','-mno-relax','-T',ROOT/'benchmarks/RISCV-TEST/rv32i_official/link.ld',args.program.resolve(),'-o','program.elf'])
    run([cc.with_name(cc.name.replace('gcc','objcopy')),'-O','binary','--remove-section=.tohost','program.elf','program.bin'])
    data=(OUT/'program.bin').read_bytes()
    if len(data)>32768: raise RuntimeError('IMEM overflow')
    data=data.ljust(32768,b'\0')
    (OUT/'imem.mem').write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
    text=(SRC/'cpu.v').read_text(encoding='utf-8')
    extra=[]
    for n in range(3):
        for port,wire,new in [('bus_ack',f'bus_s{n}_ack',f'native_ack{n}'),('r_data',f'bus_s{n}_dat_i',f'native_data{n}')]:
            text,hits=re.subn(r'\.'+port+r'\s*\(\s*'+wire+r'\s*\)',f'.{port}({new})',text)
            assert hits==1
        extra.append(f'wire native_ack{n}; wire [31:0] native_data{n}; response_delay delay{n}(clk,rst_n,native_ack{n},native_data{n},bus_s{n}_ack,bus_s{n}_dat_i);')
    (OUT/'cpu_delayed.v').write_text(text.replace('endmodule','\n'.join(extra)+'\nendmodule'),encoding='utf-8')
    run([shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe','-g2012','-I',SRC,'-s','privileged_regression_tb','-o','test.vvp',*[p for p in SRC.glob('*.v') if p.name not in ('cpu.v','top.v')],OUT/'cpu_delayed.v',ROOT/'sim_1/new/privileged_regression_tb.v',ROOT/'sim_1/new/memory_regression_tb.v'])
    logs=[]
    for delay in ((0,7,19) if args.freertos else (0,3,19,50)):
        output=run([shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe','test.vvp',f'+DELAY={delay}',*(['+TRACE'] if args.trace else [])])
        logs.append(f'delay={delay}\n'+output); print(logs[-1],flush=True)
    if not args.freertos:
        output=run([shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe','test.vvp','+DELAY=19','+RESET_WFI'])
        logs.append('reset during WFI\n'+output); print(logs[-1],flush=True)
    (OUT/'results.log').write_text('\n'.join(logs))
if __name__=='__main__': main()
