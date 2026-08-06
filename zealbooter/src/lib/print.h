#ifndef __PRINT_H__
#define __PRINT_H__

#include <limine.h>
#include <stdbool.h>

bool fb_console_init(struct limine_framebuffer *fb);
int printf(const char *format, ...);

#endif // __PRINT_H__
