#include "FreeRTOS.h"
#include "task.h"
#include <stddef.h>
#include <stdint.h>

static StaticTask_t task_buffers[3];
static StackType_t stacks[3][256];
static volatile uint32_t progress[2];

void platform_fail(unsigned code) {
    __asm__ volatile("csrci mstatus,8" ::: "memory");
    *(volatile uint32_t *)0xf000000c=code;
    *(volatile uint32_t *)0xf0000008=1;
    for(;;) __asm__ volatile("wfi");
}
void *memset(void *dest,int value,size_t n) {
    unsigned char *p=dest;
    while(n--) *p++=(unsigned char)value;
    return dest;
}
void *memcpy(void *dest,const void *src,size_t n) {
    unsigned char *p=dest; const unsigned char *q=src;
    while(n--) *p++=*q++;
    return dest;
}
static void worker(void *arg) {
    unsigned index=(unsigned)(uintptr_t)arg;
    register uint32_t guard __asm__("s2")=0x13579bdfu+index;
    taskYIELD(); /* exercise ECALL yield as well as timer preemption */
    for(;;) {
        __asm__ volatile("" : "+r"(guard));
        if(guard!=0x13579bdfu+index) platform_fail(0xf002);
        ++progress[index];
        if((progress[index]&255)==0) {
            taskENTER_CRITICAL();
            taskENTER_CRITICAL();
            uint32_t status;
            __asm__ volatile("csrr %0,mstatus" : "=r"(status));
            if(status&8) platform_fail(0xf003);
            taskEXIT_CRITICAL();
            taskEXIT_CRITICAL();
        }
        /* No blocking or yielding here: both workers can progress only if
           actual timer interrupts preempt and restore their contexts. */
    }
}
static void monitor(void *unused) {
    (void)unused;
    for(unsigned i=0;i<4;i++) vTaskDelay(5);
    if(progress[0]<100 || progress[1]<100 || xTaskGetTickCount()<20)
        platform_fail(0xf004);
    platform_fail(0); /* tohost success */
}
int main(void) {
    if(!xTaskCreateStatic(worker,"workerA",256,(void *)0,1,stacks[0],&task_buffers[0])) platform_fail(0xf005);
    if(!xTaskCreateStatic(worker,"workerB",256,(void *)1,1,stacks[1],&task_buffers[1])) platform_fail(0xf006);
    if(!xTaskCreateStatic(monitor,"monitor",256,0,2,stacks[2],&task_buffers[2])) platform_fail(0xf007);
    vTaskStartScheduler();
    platform_fail(0xf008);
    return 0;
}
