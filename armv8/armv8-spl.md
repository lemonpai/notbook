
# armv8 spl分析

## lds 分析

首先分析`arch/arm/cpu/armv8/u-boot-spl.lds`文件，文件内容如下。

1. 定义内存块

```python
# 其中通过 MEMORY 在 sram 中和 sdram 中定义两个存储区域
# ORIGIN : 内存的起始地址
# LENGTH : 内存块的长度 
MEMORY { .sram : ORIGIN = CONFIG_SPL_TEXT_BASE,
		LENGTH = CONFIG_SPL_MAX_SIZE }
MEMORY { .sdram : ORIGIN = CONFIG_SPL_BSS_START_ADDR,
		LENGTH = CONFIG_SPL_BSS_MAX_SIZE }
```

2. 定义输出格式和入口函数

```python
# 输出格式 ELF64 小端 64位
OUTPUT_FORMAT("elf64-littleaarch64", "elf64-littleaarch64", "elf64-littleaarch64")
# 目标平台 aarch64
OUTPUT_ARCH(aarch64)
# 入口函数 arch/arm/cpu/armv8/start.S 中
ENTRY(_start)
```

3. 定义段

```python
# SECTIONS 段
# sram
#  - text   代码段 
#  - rodata 只读数据段
#  - data   数据段
#  - u_boot_list 
#  - image_copy_end
#  - end
#
# sdram
#  - bss_start
#  - bss
#  - bss_end


SECTIONS
{
	.text : {
		. = ALIGN(8);
		*(.__image_copy_start)
		CPUDIR/start.o (.text*)
		*(.text*)
	} >.sram

	.rodata : {
		. = ALIGN(8);
		*(SORT_BY_ALIGNMENT(SORT_BY_NAME(.rodata*)))
	} >.sram

	.data : {
		. = ALIGN(8);
		*(.data*)
	} >.sram

	.u_boot_list : {
		. = ALIGN(8);
		KEEP(*(SORT(.u_boot_list*)));
	} >.sram

	.image_copy_end : {
		. = ALIGN(8);
		*(.__image_copy_end)
	} >.sram

	.end : {
		. = ALIGN(8);
		*(.__end)
	} >.sram

	_image_binary_end = .;

	.bss_start (NOLOAD) : {
		. = ALIGN(8);
		KEEP(*(.__bss_start));
	} >.sdram

	.bss (NOLOAD) : {
		*(.bss*)
		 . = ALIGN(8);
	} >.sdram

	.bss_end (NOLOAD) : {
		KEEP(*(.__bss_end));
	} >.sdram

	/DISCARD/ : { *(.dynsym) }
	/DISCARD/ : { *(.dynstr*) }
	/DISCARD/ : { *(.dynamic*) }
	/DISCARD/ : { *(.plt*) }
	/DISCARD/ : { *(.interp*) }
	/DISCARD/ : { *(.gnu*) }
}
```

## start.S 分析

文件`arch/arm/cpu/armv8/start.S`

```c
.globl	_start
_start:
#ifdef CONFIG_ENABLE_ARM_SOC_BOOT0_HOOK
/*
 * Various SoCs need something special and SoC-specific up front in
 * order to boot, allow them to set that in their boot0.h file and then
 * use it here.
 */
#include <asm/arch/boot0.h>
#else
	b	reset
#endif
```

通过定义`CONFIG_ENABLE_ARM_SOC_BOOT0_HOOK`设置`boot0`启动，一般情况下不需要设置，
直接跳转到`reset`

```c
reset:
	/* Allow the board to save important registers */
	b	save_boot_params
.globl	save_boot_params_ret
save_boot_params_ret:

#ifdef CONFIG_SYS_RESET_SCTRL
	# 操作sctrl的值，以配置相关设置
	bl reset_sctrl
#endif
```
tips
- B   跳转指令
- BL  带返回的跳转指令
- BLX 带返回和状态切换的跳转指令
- BX  带状态切换的跳转指令

跳转到`save_boot_params`后再转到`save_boot_params_ret`。
如果设置了`CONFIG_SYS_RESET_SCTRL`，则跳转到`reset_sctrl`，代码如下。

```c
#ifdef CONFIG_SYS_RESET_SCTRL
reset_sctrl:
	switch_el x1, 3f, 2f, 1f
3:
	mrs	x0, sctlr_el3
	b	0f
2:
	mrs	x0, sctlr_el2
	b	0f
1:
	mrs	x0, sctlr_el1

0:
	ldr	x1, =0xfdfffffa
	and	x0, x0, x1

	switch_el x1, 6f, 5f, 4f
6:
	msr	sctlr_el3, x0
	b	7f
5:
	msr	sctlr_el2, x0
	b	7f
4:
	msr	sctlr_el1, x0

7:
	dsb	sy
	isb
	b	__asm_invalidate_tlb_all
	ret
#endif

```

其中`switch`的宏定义在`arch/arm/include/asm/macro.h`中

```c
/*
 * Branch according to exception level
 */
.macro	switch_el, xreg, el3_label, el2_label, el1_label
	mrs	\xreg, CurrentEL                                                (1)
	cmp	\xreg, 0xc                                                      (2)
	b.eq	\el3_label                                                  (3)
	cmp	\xreg, 0x8
	b.eq	\el2_label
	cmp	\xreg, 0x4
	b.eq	\el1_label
.endm
```

对应于`C`代码为，其功能为获取当前`CurrentEL`的值，并与`0xC`、`0x8`、`0x4`进行比较，判断特权
值并跳转到相应的函数

```c
int switch_el(int* xreg, int el3_label, int el2_label, int el1_label) {
    *xreg = CurrentEL;
    if (xreg == 0xC)     
        return el3_label;
    if (xreg == 0x8)     
        return el2_label;
    if (xreg == 0x4)     
        return el1_label;
}
```

`reset_sctrl`翻译为C语言如下

```c
void reset_sctrl() {
    int x0, x1, x2, x3;
    int el = switch_el(&x1, 3, 2, 1);
    switch (el) {
        case 3 : x0 = sctlr_el3; break;
        case 2 : x0 = sctlr_el2; break;
        case 1 : x0 = sctlr_el1: break;
        default return;
    }
    x1 = 0xfdfffffa;
    x0 = x0 & x1;
    int el = switch_el(&x1, 6, 5, 4);
    switch (el) {
        case 6 : sctlr_el3 = x0; break;
        case 5 : sctlr_el2 = x0; break;
        case 4 : sctlr_el1 = x0: break;
        default return;
    }
    dsb(); // 数据同步隔离，仅当所有在它前面的存储器访问操作都执行完毕后，才执行在它后面的指令
    isb(); // 指令同步隔离，清洗流水线，以保证所有它前面的指令都执行完毕之后，才执行它后面的指令
    __asm_invalidate_tlb_all(); // 用于失效tlb(物理地址和虚拟地址转换表)中的内容
    return;
}
```

`__asm_invalidate_tlb_all`代码如下

```c
ENTRY(__asm_invalidate_tlb_all)
	switch_el x9, 3f, 2f, 1f
3:	tlbi	alle3
	dsb	sy
	isb
	b	0f
2:	tlbi	alle2
	dsb	sy
	isb
	b	0f
1:	tlbi	vmalle1
	dsb	sy
	isb
0:
	ret
ENDPROC(__asm_invalidate_tlb_all)
```

`__asm_invalidate_tlb_all`翻译为C语言如下

```c
void __asm_invalidate_tlb_all() {
    int x9;
    int el = switch_el(&x9, 3, 2, 1);
    switch (el) {
        case 3 : tbli(alle3);   break;
        case 2 : tbli(alle2);   break;
        case 1 : tbli(vmalle1): break;
        default return;
    }
    // 等待指令完成
    dsb();
    isb();
}
```

`reset_sctrl`后代码如下：

```c
adr	x0, vectors
	switch_el x1, 3f, 2f, 1f
3:	msr	vbar_el3, x0
	mrs	x0, scr_el3
	orr	x0, x0, #0xf			/* SCR_EL3.NS|IRQ|FIQ|EA */
	msr	scr_el3, x0
	msr	cptr_el3, xzr			/* Enable FP/SIMD */
#ifdef COUNTER_FREQUENCY
	ldr	x0, =COUNTER_FREQUENCY
	msr	cntfrq_el0, x0			/* Initialize CNTFRQ */
#endif
	b	0f
2:	msr	vbar_el2, x0
	mov	x0, #0x33ff
	msr	cptr_el2, x0			/* Enable FP/SIMD */
	b	0f
1:	msr	vbar_el1, x0
	mov	x0, #3 << 20
	msr	cpacr_el1, x0			/* Enable FP/SIMD */
0:
```

翻译为C语言如下

```c
int  x1;
int* x0 = vectors
int el = switch_el(&x1, 3, 2, 1);
switch (el) {
    case 3 : 
        vbar_el3 = x0;
        x0 = scr_el3;
        x0 |= 0xF;
        scr_el3 = x0;
        cptr_el3 = xzr;
#ifdef COUNTER_FREQUENCY
        x0 = COUNTER_FREQUENCY;
        cntfrq_el0 = x0;
#endif
        break;
    case 2 : 
        vbar_el2 = x0;
        x0 = 0x33FF;
        cptr_el2 = x0;
        break;
    case 1 :
        vbar_el1 = x0;
        x0 = 3 << 20;
        cpacr_el1 = x0;
        break;
    default return;
}
```

