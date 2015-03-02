local ffi = require "ffi"

ffi.cdef [[typedef void * GC_PTR;
typedef unsigned long GC_word;
typedef long GC_signed_word;
extern unsigned  GC_get_version(void);
extern  GC_word GC_gc_no;
extern GC_word  GC_get_gc_no(void);
typedef void * ( * GC_oom_func)(size_t );
extern  GC_oom_func GC_oom_fn;
extern void  GC_set_oom_fn(GC_oom_func) ;
extern GC_oom_func  GC_get_oom_fn(void);
typedef void ( * GC_on_heap_resize_proc)(GC_word );
extern  GC_on_heap_resize_proc GC_on_heap_resize;
extern void  GC_set_on_heap_resize(GC_on_heap_resize_proc);
extern GC_on_heap_resize_proc  GC_get_on_heap_resize(void);
extern  int GC_find_leak;
extern void  GC_set_find_leak(int);
extern int  GC_get_find_leak(void);
extern  int GC_all_interior_pointers;
extern void  GC_set_all_interior_pointers(int);
extern int  GC_get_all_interior_pointers(void);
extern  int GC_finalize_on_demand;
extern void  GC_set_finalize_on_demand(int);
extern int  GC_get_finalize_on_demand(void);
extern  int GC_java_finalization;
extern void  GC_set_java_finalization(int);
extern int  GC_get_java_finalization(void);
typedef void ( * GC_finalizer_notifier_proc)(void);
extern  GC_finalizer_notifier_proc GC_finalizer_notifier;
extern void  GC_set_finalizer_notifier(GC_finalizer_notifier_proc);
extern GC_finalizer_notifier_proc  GC_get_finalizer_notifier(void);
extern
int GC_dont_gc;
extern  int GC_dont_expand;
extern void  GC_set_dont_expand(int);
extern int  GC_get_dont_expand(void);
extern  int GC_use_entire_heap;
extern  int GC_full_freq;
extern void  GC_set_full_freq(int);
extern int  GC_get_full_freq(void);
extern  GC_word GC_non_gc_bytes;
extern void  GC_set_non_gc_bytes(GC_word);
extern GC_word  GC_get_non_gc_bytes(void);
extern  int GC_no_dls;
extern void  GC_set_no_dls(int);
extern int  GC_get_no_dls(void);
extern  GC_word GC_free_space_divisor;
extern void  GC_set_free_space_divisor(GC_word);
extern GC_word  GC_get_free_space_divisor(void);
extern  GC_word GC_max_retries;
extern void  GC_set_max_retries(GC_word);
extern GC_word  GC_get_max_retries(void);
extern  char *GC_stackbottom;
extern  int GC_dont_precollect;
extern void  GC_set_dont_precollect(int);
extern int  GC_get_dont_precollect(void);
extern  unsigned long GC_time_limit;
extern void  GC_set_time_limit(unsigned long);
extern unsigned long  GC_get_time_limit(void);
extern void  GC_set_pages_executable(int);
extern int  GC_get_pages_executable(void);
extern void  GC_set_handle_fork(int);
extern void  GC_atfork_prepare(void);
extern void  GC_atfork_parent(void);
extern void  GC_atfork_child(void);
extern void  GC_init(void);
extern   void * 
GC_malloc(size_t );
extern   void * 
GC_malloc_atomic(size_t );
extern  char *  GC_strdup(const char *);
extern  char * 
GC_strndup(const char *, size_t) ;
extern   void * 
GC_malloc_uncollectable(size_t );
extern   void * 
GC_malloc_stubborn(size_t );
extern   void * 
GC_memalign(size_t , size_t );
extern int  GC_posix_memalign(void ** , size_t ,
size_t ) ;
extern void  GC_free(void *);
extern void  GC_change_stubborn(const void *) ;
extern void  GC_end_stubborn_change(const void *) ;
extern void *  GC_base(void * );
extern int  GC_is_heap_ptr(const void *);
extern size_t  GC_size(const void * ) ;
extern void *  GC_realloc(void * ,
size_t )
;
extern int  GC_expand_hp(size_t );
extern void  GC_set_max_heap_size(GC_word );
extern void  GC_exclude_static_roots(void * ,
void * );
extern void  GC_clear_roots(void);
extern void  GC_add_roots(void * ,
void * );
extern void  GC_remove_roots(void * ,
void * );
extern void  GC_register_displacement(size_t );
extern void  GC_debug_register_displacement(size_t );
extern void  GC_gcollect(void);
extern void  GC_gcollect_and_unmap(void);
typedef int ( * GC_stop_func)(void);
extern int  GC_try_to_collect(GC_stop_func )
;
extern void  GC_set_stop_func(GC_stop_func )
;
extern GC_stop_func  GC_get_stop_func(void);
extern size_t  GC_get_heap_size(void);
extern size_t  GC_get_free_bytes(void);
extern size_t  GC_get_unmapped_bytes(void);
extern size_t  GC_get_bytes_since_gc(void);
extern size_t  GC_get_total_bytes(void);
extern void  GC_get_heap_usage_safe(GC_word * ,
GC_word * ,
GC_word * ,
GC_word * ,
GC_word * );
struct GC_prof_stats_s {
GC_word heapsize_full;
GC_word free_bytes_full;
GC_word unmapped_bytes;
GC_word bytes_allocd_since_gc;
GC_word allocd_bytes_before_gc;
GC_word non_gc_bytes;
GC_word gc_no;
GC_word markers_m1;
GC_word bytes_reclaimed_since_gc;
GC_word reclaimed_bytes_before_gc;
};
extern size_t  GC_get_prof_stats(struct GC_prof_stats_s *,
size_t );
extern void  GC_disable(void);
extern int  GC_is_disabled(void);
extern void  GC_enable(void);
extern void  GC_enable_incremental(void);
extern int  GC_incremental_protection_needs(void);
extern int  GC_collect_a_little(void);
extern   void * 
GC_malloc_ignore_off_page(size_t );
extern   void * 
GC_malloc_atomic_ignore_off_page(size_t );
extern   void * 
GC_malloc_atomic_uncollectable(size_t );
extern   void * 
GC_debug_malloc_atomic_uncollectable(size_t, const char * s, int i);
extern   void * 
GC_debug_malloc(size_t , const char * s, int i);
extern   void * 
GC_debug_malloc_atomic(size_t , const char * s, int i);
extern  char * 
GC_debug_strdup(const char *, const char * s, int i);
extern  char * 
GC_debug_strndup(const char *, size_t, const char * s, int i)
;
extern   void * 
GC_debug_malloc_uncollectable(size_t ,
const char * s, int i);
extern   void * 
GC_debug_malloc_stubborn(size_t , const char * s, int i);
extern   void * 
GC_debug_malloc_ignore_off_page(size_t ,
const char * s, int i);
extern   void * 
GC_debug_malloc_atomic_ignore_off_page(size_t ,
const char * s, int i);
extern void  GC_debug_free(void *);
extern void *  GC_debug_realloc(void * ,
size_t , const char * s, int i)
;
extern void  GC_debug_change_stubborn(const void *) ;
extern void  GC_debug_end_stubborn_change(const void *)
;
extern   void * 
GC_debug_malloc_replacement(size_t );
extern   void * 
GC_debug_realloc_replacement(void * ,
size_t );
typedef void ( * GC_finalization_proc)(void * ,
void * );
extern void  GC_register_finalizer(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_debug_register_finalizer(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_register_finalizer_ignore_self(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_debug_register_finalizer_ignore_self(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_register_finalizer_no_order(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_debug_register_finalizer_no_order(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_register_finalizer_unreachable(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern void  GC_debug_register_finalizer_unreachable(void * ,
GC_finalization_proc , void * ,
GC_finalization_proc * , void ** )
;
extern int  GC_register_disappearing_link(void ** )
;
extern int  GC_general_register_disappearing_link(void ** ,
const void * )
 ;
extern int  GC_move_disappearing_link(void ** ,
void ** )
;
extern int  GC_unregister_disappearing_link(void ** );
extern int  GC_register_long_link(void ** ,
const void * )
 ;
extern int  GC_move_long_link(void ** ,
void ** )
;
extern int  GC_unregister_long_link(void ** );
extern int  GC_should_invoke_finalizers(void);
extern int  GC_invoke_finalizers(void);
extern void  GC_noop1(GC_word);
typedef void ( * GC_warn_proc)(char * ,
GC_word );
extern void  GC_set_warn_proc(GC_warn_proc ) ;
extern GC_warn_proc  GC_get_warn_proc(void);
extern void  GC_ignore_warn_proc(char *, GC_word);
extern void  GC_set_log_fd(int);
typedef void ( * GC_abort_func)(const char * );
extern void  GC_set_abort_func(GC_abort_func) ;
extern GC_abort_func  GC_get_abort_func(void);
typedef GC_word GC_hidden_pointer;
typedef void * ( * GC_fn_type)(void * );
extern void *  GC_call_with_alloc_lock(GC_fn_type ,
void * ) ;
struct GC_stack_base {
void * mem_base;
};
typedef void * ( * GC_stack_base_func)(
struct GC_stack_base * , void * );
extern void *  GC_call_with_stack_base(GC_stack_base_func ,
void * ) ;
extern void *  GC_do_blocking(GC_fn_type ,
void * ) ;
extern void *  GC_call_with_gc_active(GC_fn_type ,
void * ) ;
extern int  GC_get_stack_base(struct GC_stack_base *)
;
extern void *  GC_same_obj(void * , void * );
extern void *  GC_pre_incr(void **, ptrdiff_t )
;
extern void *  GC_post_incr(void **, ptrdiff_t )
;
extern void *  GC_is_visible(void * );
extern void *  GC_is_valid_displacement(void * );
extern void  GC_dump(void);
extern void ( * GC_same_obj_print_proc)(void * ,
void * );
extern void ( * GC_is_valid_displacement_print_proc)(void *);
extern void ( * GC_is_visible_print_proc)(void *);
extern  void *  GC_malloc_many(size_t );
typedef int ( * GC_has_static_roots_func)(
const char * ,
void * ,
size_t );
extern void  GC_register_has_static_roots_callback(
GC_has_static_roots_func);
extern void  GC_set_force_unmap_on_gcollect(int);
extern int  GC_get_force_unmap_on_gcollect(void);
extern void  GC_win32_free_heap(void);
]]
return ffi.load("./libgc.so")
