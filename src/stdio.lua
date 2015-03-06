local ffi = require "ffi"
ffi.cdef [[

struct __FILE;
typedef struct __FILE* FILE;

int remove (__const char *__filename) __attribute__ ((__nothrow__ , __leaf__));
int rename (__const char *__old, __const char *__new) __attribute__ ((__nothrow__ , __leaf__));

int renameat (int __oldfd, __const char *__old, int __newfd,
       __const char *__new) __attribute__ ((__nothrow__ , __leaf__));

FILE *tmpfile (void) ;
int feof(FILE* file);
char *tmpnam (char *__s) __attribute__ ((__nothrow__ , __leaf__)) ;

char *tmpnam_r (char *__s) __attribute__ ((__nothrow__ , __leaf__)) ;
char *tempnam (__const char *__dir, __const char *__pfx)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__)) ;

int fclose (FILE *__stream);
int fflush (FILE *__stream);

int fflush_unlocked (FILE *__stream);

FILE *fopen (__const char *__restrict __filename,
      __const char *__restrict __modes) ;
FILE *freopen (__const char *__restrict __filename,
        __const char *__restrict __modes,
        FILE *__restrict __stream) ;

FILE *fdopen (int __fd, __const char *__modes) __attribute__ ((__nothrow__ , __leaf__)) ;
FILE *fmemopen (void *__s, size_t __len, __const char *__modes)
  __attribute__ ((__nothrow__ , __leaf__)) ;
FILE *open_memstream (char **__bufloc, size_t *__sizeloc) __attribute__ ((__nothrow__ , __leaf__)) ;

void setbuf (FILE *__restrict __stream, char *__restrict __buf) __attribute__ ((__nothrow__ , __leaf__));
int setvbuf (FILE *__restrict __stream, char *__restrict __buf,
      int __modes, size_t __n) __attribute__ ((__nothrow__ , __leaf__));

void setbuffer (FILE *__restrict __stream, char *__restrict __buf,
         size_t __size) __attribute__ ((__nothrow__ , __leaf__));
void setlinebuf (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));

int fprintf (FILE *__restrict __stream,
      __const char *__restrict __format, ...);
int printf (__const char *__restrict __format, ...);
int sprintf (char *__restrict __s,
      __const char *__restrict __format, ...) __attribute__ ((__nothrow__));
int vfprintf (FILE *__restrict __s, __const char *__restrict __format,
       __gnuc_va_list __arg);
int vprintf (__const char *__restrict __format, __gnuc_va_list __arg);
int vsprintf (char *__restrict __s, __const char *__restrict __format,
       __gnuc_va_list __arg) __attribute__ ((__nothrow__));


int snprintf (char *__restrict __s, size_t __maxlen,
       __const char *__restrict __format, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 4)));
int vsnprintf (char *__restrict __s, size_t __maxlen,
        __const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 0)));

int vdprintf (int __fd, __const char *__restrict __fmt,
       __gnuc_va_list __arg)
     __attribute__ ((__format__ (__printf__, 2, 0)));
int dprintf (int __fd, __const char *__restrict __fmt, ...)
     __attribute__ ((__format__ (__printf__, 2, 3)));

int fscanf (FILE *__restrict __stream,
     __const char *__restrict __format, ...) ;
int scanf (__const char *__restrict __format, ...) ;
int sscanf (__const char *__restrict __s,
     __const char *__restrict __format, ...) __attribute__ ((__nothrow__ , __leaf__));
int fscanf (FILE *__restrict __stream, __const char *__restrict __format, ...) __asm__ ("" "__isoc99_fscanf") ;
int scanf (__const char *__restrict __format, ...) __asm__ ("" "__isoc99_scanf") ;
int sscanf (__const char *__restrict __s, __const char *__restrict __format, ...) __asm__ ("" "__isoc99_sscanf") __attribute__ ((__nothrow__ , __leaf__));


int vfscanf (FILE *__restrict __s, __const char *__restrict __format,
      __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 2, 0))) ;
int vscanf (__const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 1, 0))) ;
int vsscanf (__const char *__restrict __s,
      __const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__format__ (__scanf__, 2, 0)));
int vfscanf (FILE *__restrict __s, __const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vfscanf")
     __attribute__ ((__format__ (__scanf__, 2, 0))) ;
int vscanf (__const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vscanf")
     __attribute__ ((__format__ (__scanf__, 1, 0))) ;
int vsscanf (__const char *__restrict __s, __const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vsscanf") __attribute__ ((__nothrow__ , __leaf__))
     __attribute__ ((__format__ (__scanf__, 2, 0)));


int fgetc (FILE *__stream);
int getc (FILE *__stream);
int getchar (void);

int getc_unlocked (FILE *__stream);
int getchar_unlocked (void);
int fgetc_unlocked (FILE *__stream);

int fputc (int __c, FILE *__stream);
int putc (int __c, FILE *__stream);
int putchar (int __c);

int fputc_unlocked (int __c, FILE *__stream);
int putc_unlocked (int __c, FILE *__stream);
int putchar_unlocked (int __c);
int getw (FILE *__stream);
int putw (int __w, FILE *__stream);

char *fgets (char *__restrict __s, int __n, FILE *__restrict __stream)
     ;
char *gets (char *__s) ;

size_t __getdelim (char **__restrict __lineptr,
          size_t *__restrict __n, int __delimiter,
          FILE *__restrict __stream) ;
size_t getdelim (char **__restrict __lineptr,
        size_t *__restrict __n, int __delimiter,
        FILE *__restrict __stream) ;
size_t getline (char **__restrict __lineptr,
       size_t *__restrict __n,
       FILE *__restrict __stream) ;

int fputs (__const char *__restrict __s, FILE *__restrict __stream);
int puts (__const char *__s);
int ungetc (int __c, FILE *__stream);
size_t fread (void *__restrict __ptr, size_t __size,
       size_t __n, FILE *__restrict __stream) ;
size_t fwrite (__const void *__restrict __ptr, size_t __size,
        size_t __n, FILE *__restrict __s) ;

size_t fread_unlocked (void *__restrict __ptr, size_t __size,
         size_t __n, FILE *__restrict __stream) ;
size_t fwrite_unlocked (__const void *__restrict __ptr, size_t __size,
          size_t __n, FILE *__restrict __stream) ;

long int ftell (FILE *__stream) ;
void rewind (FILE *__stream);
]]
