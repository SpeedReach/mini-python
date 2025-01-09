.data
    none: .string "None"
    true: .string "True"
    false: .string "False"
    integer: .string "%d"
    newline: .string "\n"
    panic_str: .string "error\n\0"
.section .note.GNU-stack,"",@progbits
.text

.macro malloc size
    subq    $8, %rsp
    movq    \size, (%rsp)
    call my_malloc
    addq    $8, %rsp
.endm

my_malloc:
  pushq   %rbp
  movq    %rsp, %rbp
  andq    $-16, %rsp
  movq    16(%rbp), %rdi
  call    malloc
  movq    %rbp, %rsp
  popq    %rbp
  ret

.macro print
    call simple_print
    call print_next_line
.endm

__list:
  pushq   %rbp
  movq    %rsp, %rbp
  movq    %rbp, %rsp
  popq    %rbp
  ret
__range:
  pushq   %rbp
  movq    %rsp, %rbp
  movq    16(%rbp), %rbx
  movq    (%rbx), %rax
  cmpq    $2, %rax
  jne runtime_panic
  movq    8(%rbx), %rax
  pushq   %rax #n
  pushq   $0   #i
  addq    $16, %rax
  imulq $8, %rax 
  malloc  %rax
  movq    $4, (%rax)
  movq    8(%rbx), %rcx
  movq    %rcx, 8(%rax)
  addq    $16, %rax
  pushq   %rax #ptr
range_loop:
  movq    8(%rsp), %rax  #i
  movq    16(%rsp), %rbx #n
  cmpq    %rbx, %rax
  jge range_end
  malloc  $16
  movq    $2, (%rax)
  movq    8(%rsp), %rcx
  movq    %rcx, 8(%rax)

  imulq   $8, %rcx
  movq    (%rsp), %rdx
  addq    %rcx, %rdx
  movq    %rax, (%rdx)
  movq    8(%rsp), %rcx
  addq    $1, %rcx
  movq    %rcx, 8(%rsp)
  jmp range_loop

range_end:
  movq    (%rsp), %rax
  subq    $16, %rax
  addq    $24, %rsp
  movq    %rbp, %rsp
  popq    %rbp
  ret



__len:
  pushq   %rbp
  movq    %rsp, %rbp
  movq    16(%rbp), %rbx
  movq    (%rbx), %rax
  cmpq    $4, %rax
  je  len_list
  cmpq    $3, %rax
  je  len_str
  jmp runtime_panic

len_str:
len_list:
  malloc  $16
  movq    $2, (%rax)
  movq    8(%rbx), %rbx
  movq    %rbx, 8(%rax)
  movq    %rbp, %rsp
  popq    %rbp
  ret  


not:
  pushq   %rbp
  movq    %rsp, %rbp
  movq    16(%rbp), %rbx
  pushq   %rbx
  call    is_bool
  addq    $8, %rsp
  cmpq    $0, %rax
  je  not_return_true
  jmp not_return_false
not_return_true:
  malloc  $16
  movq    $1, (%rax)
  movq    $1, 8(%rax)
  jmp not_end
not_return_false:
  malloc  $16
  movq    $1, (%rax)
  movq    $0, 8(%rax)
not_end:
  movq    %rbp, %rsp
  popq    %rbp
  ret

is_bool:
  pushq   %rbp
  movq    %rsp, %rbp
  movq    16(%rbp), %rbx
  movq    (%rbx), %rax
  cmpq    $0, %rax
  je  is_bool_false
  cmpq    $1, %rax
  je  is_bool_bool
  cmpq    $2, %rax
  je  is_bool_int
  cmpq    $3, %rax
  je  is_bool_str
  cmpq    $4, %rax
  je  is_bool_list
  jmp runtime_panic
is_bool_bool:
  movq    8(%rbx), %rax
  jmp  is_bool_end
is_bool_int:
  movq    8(%rbx), %rax
  cmpq    $0, %rax
  je  is_bool_false
  je  is_bool_true
is_bool_str:
  movq    8(%rbx), %rax
  cmpq    $0, %rax
  je  is_bool_false
  je  is_bool_true
is_bool_list:
  movq    8(%rbx), %rax
  cmpq    $0, %rax
  je  is_bool_false
  je  is_bool_true
is_bool_true:
  movq    $1, %rax
  jmp  is_bool_end
is_bool_false:
  movq    $0, %rax
is_bool_end:
  movq    %rbp, %rsp
  popq    %rbp
  ret

simple_print:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    16(%rbp), %rbx  # get arg0 , which is a pointer to the value

    movq    (%rbx), %rcx    # get the type, which is the first 64 bits

    addq    $8, %rbx        # move the pointer to the value to the next 64 bits 
    subq    $8, %rsp        # and store it as arg0 for call_print_xxx 
    movq    %rbx, (%rsp)
    cmpq    $0, %rcx
    je  call_print_none
    cmpq    $1, %rcx
    je  call_print_bool
    cmpq    $2, %rcx
    je  call_print_int
    cmpq    $3, %rcx
    je  call_print_str
    cmpq    $4, %rcx
    je  call_print_list
    jmp runtime_panic
simple_print_end:
    movq    %rbp, %rsp
    popq    %rbp
    ret

call_print_none:
    call    print_none
    jmp simple_print_end
call_print_bool:
    call    print_bool
    jmp simple_print_end
call_print_int:
    call    print_int
    jmp simple_print_end
call_print_str:
    call    print_string
    jmp simple_print_end
call_print_list:
    call    print_list
    jmp simple_print_end

print_int:
    pushq   %rbp
    movq    %rsp, %rbp 
    andq    $-16, %rsp              # 16bit alignment

    movq    16(%rbp), %rsi          # Get arg0 , which is the pointer to the int.
    movq    (%rsi), %rsi            # Move the int to %rsi, which is the second argument in printf 
    leaq    integer(%rip), %rdi     # Load address of format string into %rdi
    xorq    %rax, %rax              # Set %rax to 0 as required for variadic functions

    call    printf                  # Call the `printf` function
    movq    %rbp, %rsp
    popq    %rbp
    ret 

print_none:
    pushq %rbp
    movq    %rsp, %rbp 
    andq $-16, %rsp
    leaq none(%rip), %rdi   # Load address of format string into %rdi
    xorq %rax, %rax         # Set %rax to 0 as required for variadic functions
    call printf             # Call the `printf` function
    movq %rbp, %rsp
    popq %rbp
    ret
#Arg 1 = ptr to bool memory 
print_bool:
    pushq   %rbp
    movq    %rsp, %rbp 
    andq    $-16, %rsp
    movq    16(%rbp), %rax
    movq    (%rax), %rax
    cmpq    $0, %rax
    je  print_false
    jmp print_true

print_true:
    leaq    true(%rip), %rdi    # Load address of format string into %rdi
    xorq    %rax, %rax          # Set %rax to 0 as required for variadic functions
    call    printf              # Call the `printf` function

    movq    %rbp, %rsp
    popq    %rbp
    ret 
print_false:
    leaq    false(%rip), %rdi   # Load address of format string into %rdi
    xorq    %rax, %rax          # Set %rax to 0 as required for variadic functions
    call    printf              # Call the `printf` function

    movq    %rbp, %rsp
    popq    %rbp
    ret 

# Basically, we do a 
# for(int i=0;i<n;i++) 
#   putchar(s[i]) 
print_string:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    16(%rbp), %rbx          # Get arg0 , which is the pointer to the length
    subq    $24, %rsp               # which is -8(%rbp)
    movq    (%rbx), %rcx            # Save the length on -8(%rbp)
    movq    %rcx, 16(%rsp)            

    movq    %rbx, %rcx              # Store the pointer to the string on -16(%rbp)
    addq    $8, %rcx                # Add 1 byte, because the string starts at second index.
    movq    %rcx, 8(%rsp)

print_string_for_init:
    movq    $0, (%rsp)              # Initialize i=0, and store it on -24(%rbp)
print_string_for_cond:
    movq    -8(%rbp), %rbx          # Set rbx to length
    movq    -24(%rbp), %rcx         # Set rcx to i
    cmpq    %rbx, %rcx 
    jge print_string_for_end
print_string_for_inner:
    movq    -16(%rbp), %rbx         # Set rbx to the pointer to the start of the string
    movq    -24(%rbp), %rcx         # Set rcx to i
    #imulq   $8, %rcx                # Since every char is 8 bytes in mini-python, we have to * 8
    addq    %rbx, %rcx              # Get pointer to str[i]
    movq    (%rcx), %rcx            # Move the char at str[i] to rcx 
                                #
    subq    $8, %rsp                # Prepare my_putchar arg0 
    movq    %rcx, (%rsp)            # 
    call    my_putchar
    addq    $8, %rsp

    movq    -24(%rbp), %rbx         # Perform i++
    addq    $1, %rbx                #
    movq    %rbx, -24(%rbp)         #

    jmp print_string_for_cond
print_string_for_end:

    movq    %rbp, %rsp
    popq    %rbp
    ret 

my_putchar:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    16(%rbp), %rdi
    andq    $-16, %rsp
    call    putchar
    movq    %rbp, %rsp
    popq    %rbp
    ret

my_strcmp:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    16(%rbp), %rdi
    movq    24(%rbp), %rsi
    andq    $-16, %rsp
    call    strcmp
    movq    %rbp, %rsp
    popq    %rbp
    ret

my_strcpy:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    16(%rbp), %rdi
    movq    24(%rbp), %rsi
    andq    $-16, %rsp
    call    strcpy
    movq    %rbp, %rsp
    popq    %rbp
    ret
my_memcpy:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    32(%rbp), %rdi
    movq    24(%rbp), %rsi
    movq    16(%rbp), %rdx
    andq    $-16, %rsp
    call    memcpy
    movq    %rbp, %rsp
    popq    %rbp
    ret

print_next_line:
    leaq    newline(%rip), %rdi     # Load address of format string into %rdi
    xorq    %rax, %rax              # Set %rax to 0 as required for variadic functions
    call    printf                  # Call the `printf` function
    ret

print_list:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    16(%rbp), %rbx          # Get arg0 , which is the pointer to the length
    subq    $24, %rsp               # which is -8(%rbp)
    movq    (%rbx), %rcx            # Save the length on -8(%rbp)
    movq    %rcx, 16(%rsp)            

    movq    %rbx, %rcx              # Store the pointer to the string on -16(%rbp)
    addq    $8, %rcx                # Add 1 byte, because the list starts at second index.
    movq    %rcx, 8(%rsp)

    subq    $8, %rsp                # Print [
    movq    $91, (%rsp)
    call    my_putchar
    addq    $8, %rsp

print_list_for_init:
    movq    $0, (%rsp)              # Initialize i=0, and store it on -24(%rbp)
print_list_for_inner:
    movq    -8(%rbp), %rbx          # Check if we are at the end of the list
    movq    -24(%rbp), %rcx         # Set rcx to i
    cmpq    %rbx, %rcx 
    jge print_list_for_end
    movq    -16(%rbp), %rbx         # Set rbx to the pointer to the start of the string
    movq    -24(%rbp), %rcx         # Set rcx to i
    imulq   $8, %rcx                # Since every char is 8 bytes in mini-python, we have to * 8
    addq    %rbx, %rcx              # Get pointer to str[i]
    movq    (%rcx), %rcx            # Move the char at str[i] to rcx 
                                    #
    pushq   %rcx                    # Prepare my_putchar arg0
    call    simple_print
    popq    %rcx

    movq    -24(%rbp), %rbx         # Perform i++
    addq    $1, %rbx                #
    movq    %rbx, -24(%rbp)         #

    movq    -8(%rbp), %rbx          # Check if we are at the end of the list
    movq    -24(%rbp), %rcx         # Set rcx to i
    cmpq    %rbx, %rcx 
    jge print_list_for_end
    
    subq    $8, %rsp                # Print ,
    movq    $44, (%rsp)
    call    my_putchar
    addq    $8, %rsp

    subq    $8, %rsp                # Print space
    movq    $32, (%rsp)
    call    my_putchar
    addq    $8, %rsp

    jmp print_list_for_inner
print_list_for_end:

    subq    $8, %rsp                # Print ]
    movq    $93, (%rsp)
    call    my_putchar
    addq    $8, %rsp

    movq    %rbp, %rsp
    popq    %rbp
    ret 

runtime_panic:
    andq $-16, %rsp
    leaq panic_str(%rip), %rdi   # Load address of format string into %rdi
    xorq %rax, %rax         # Set %rax to 0 as required for variadic functions

    call printf             # Call the `printf` function
    movq    $60, %rax                     # System call number for `exit`
    #xorq    %rdi, %rdi                    
    movq    $1, %rdi              # Status 1 (error exit)
    syscall                           # Make the system call

_builtin_cmp:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    (%rdi), %r8
    movq    (%rsi), %r9
    cmpq    $0, %r8
    je  _cmp_none
    cmpq    $1, %r8
    je  _cmp_int
    cmpq    $2, %r8
    je  _cmp_int
    cmpq    $3, %r8
    je  _cmp_str
    cmpq    $4, %r8
    je  _cmp_list
_cmp_none:
    cmpq  $0, %r9
    je  _cmp_equal
    jmp runtime_panic

_cmp_int:
    movq    8(%rdi),   %r8
    cmpq    $1,   %r9
    je  _cmp_int_2
    cmpq    $2,   %r9
    je  _cmp_int_2
    jmp runtime_panic
_cmp_int_2:
    movq    8(%rsi),   %r9
    cmpq    %r9, %r8
    je  _cmp_equal
    jl  _cmp_smaller
    jmp _cmp_larger
_cmp_str:
    cmpq    $3, %r9
    jne   runtime_panic
    addq    $16, %rdi
    addq    $16, %rsi
    pushq   %rdi
    pushq   %rsi
    call    my_strcmp
    addq  $16, %rsp
    jmp _cmp_end

_cmp_list:
    cmpq  $4, %r9
    jne   runtime_panic    
    movq    8(%rdi), %r8
    movq    8(%rsi), %r9
    cmpq    %r9, %r8
    jg  _cmp_larger
    jl  _cmp_smaller
    pushq   %rdi
    pushq   %rsi
    pushq   %r8
    pushq   $0
_cmp_list_for:
    movq    (%rsp), %rbx
    movq    8(%rsp), %rcx
    cmpq    %rbx, %rcx
    je  _cmp_equal
    movq    (%rsp), %rbx
    movq    16(%rsp), %rcx
    movq    24(%rsp), %rdx
    imulq   $8, %rbx
    addq    $16, %rbx
    addq    %rbx, %rcx
    addq    %rbx, %rdx
    movq    (%rcx), %rsi
    movq    (%rdx), %rdi
    call   _builtin_cmp
    cmpq    $0, %rax
    jg  _cmp_larger
    jl  _cmp_smaller
    movq    (%rsp), %rbx
    addq    $1, %rbx
    movq    %rbx, (%rsp)
    jmp _cmp_list_for

_cmp_larger:
    movq    $1, %rax
    jmp _cmp_end
_cmp_smaller:
    movq    $-1, %rax
    jmp _cmp_end
_cmp_equal:
    movq    $0, %rax
    jmp _cmp_end
_cmp_end:
    movq    %rbp, %rsp
    popq    %rbp
    ret


_builtin_add:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    (%rdi), %r8           # Check if same type
    movq    (%rsi), %r9
    cmpq    %r8, %r9
    jne runtime_panic           # Should be same type
    cmpq    $0, %r8
    je  runtime_panic           # Add None is not supported
    cmpq    $1, %r8
    je  runtime_panic           # Add Bool is not supported
    cmpq    $2, %r8
    je  add_int
    cmpq    $3, %r8
    je  add_str
    cmpq    $4, %r8
    je  add_list

add_int:
    movq    8(%rdi), %r8
    movq    8(%rsi), %r9
    addq    %r8, %r9
    pushq   %r9
 
# alloc memory for add result
    malloc  $16
    movq    $2, (%rax)
    popq    %r9
    movq    %r9, 8(%rax)
    
    movq    %rbp, %rsp
    popq    %rbp
    ret
.globl main
add_str:
    pushq   %rdi
    pushq   %rsi
    movq    8(%rdi), %r8  # r8 = len(str1)
    movq    8(%rsi), %r9  # r9 = len(str2)

    addq  $16, %r8        # We have to malloc 16 + len(str1) + len(str2) + 1
    addq  %r9, %r8
    pushq   %r8
    malloc  %r8
    movq    $3, (%rax)    # Set type to string
    popq    %r8
    subq    $16, %r8
    movq    %r8, 8(%rax)  # Set len(after concat)

    movq    -8(%rbp), %rdi
    movq    %rdi, %r8     # Set r8 = str1
    addq    $16, %r8       # Set r8 = ptr(str1 start)
    pushq   %r8           

    addq    $16, %rax     # Set (rax + 16) to the destination of strcpy
    pushq   %rax

    call  my_strcpy

    movq    -8(%rbp), %rdi
    movq    8(%rdi), %rbx # Set rbx = len(str1)
    movq    (%rsp),    %rax          
    addq    %rbx, %rax

    movq    -16(%rbp), %rsi
    addq    $16, %rsi
    pushq   %rsi

    pushq %rax
    call  my_strcpy
    movq  16(%rsp),  %rax
    subq    $16, %rax 
    movq    %rbp, %rsp
    popq    %rbp
    ret
    
add_list:
    pushq   %rdi
    pushq   %rsi
    movq    8(%rdi), %r8  # r8 = len(list1)
    movq    8(%rsi), %r9  # r9 = len(list2)

    addq  %r8, %r9        # We have to malloc 16 + (len(list1) + len(list2)) * 8
    imulq $8, %r9
    addq  $16, %r9
    malloc  %r9
    pushq   %rax
    movq    $4, (%rax)    # Set type to string
    movq    -8(%rbp), %rdi
    movq    -16(%rbp), %rsi
    movq    8(%rdi), %r8  # r8 = len(list1)
    movq    8(%rsi), %r9  # r9 = len(list2)
    addq    %r8, %r9
    movq    %r9, 8(%rax)  # Set len(after concat)
    movq    -8(%rbp), %rdi
    movq    %rdi, %r8     # Set r8 = str1
      
    addq    $16, %rax     # Set (rax + 16) to the destination of strcpy
    pushq   %rax

    addq    $16, %r8       # Set r8 = ptr(str1 start)
    pushq   %r8    

    movq    8(%rdi), %r8
    imulq   $8, %r8
    pushq   %r8  

    call  my_memcpy
    
    popq    %r8
    popq    %rax
    popq    %rax
    addq    %r8, %rax
    pushq %rax

    movq    -16(%rbp), %rsi
    addq    $16, %rsi
    pushq   %rsi

    movq    -16(%rbp), %rsi
    movq    8(%rsi), %r9
    imulq   $8, %r9
    pushq   %r9
    call  my_memcpy
    movq  -24(%rbp),  %rax
    
    movq    %rbp, %rsp
    popq    %rbp
    ret

_builtin_eq:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    (%rdi), %r8
    movq    (%rsi), %r9
    cmpq    %r8, %r9
    jne _eq_false
    cmpq    $4, %r8
    je _eq_list
    call _builtin_cmp
w:
    cmpq    $0, %rax
    je    _eq_true
    jmp   _eq_false
_eq_list:
    movq    8(%rdi), %r8
    movq    8(%rsi), %r9
    cmpq    %r9, %r8
    jne _eq_false
    pushq   %rdi
    pushq   %rsi
    pushq   %r8
    pushq   $0
_eq_list_for:
    movq    (%rsp), %rbx
    movq    8(%rsp), %rcx
    cmpq    %rbx, %rcx
    je  _eq_true
    movq    (%rsp), %rbx
    movq    16(%rsp), %rcx
    movq    24(%rsp), %rdx
    imulq   $8, %rbx
    addq    $16, %rbx
    addq    %rbx, %rcx
    addq    %rbx, %rdx
    movq    (%rcx), %rsi
    movq    (%rdx), %rdi
    call   _builtin_eq
    cmpq    $0, %rax
    je _eq_false
    movq    (%rsp), %rbx
    addq    $1, %rbx
    movq    %rbx, (%rsp)
    jmp _eq_list_for

_eq_false:
    movq    $0, %rax
    jmp _eq_end
_eq_true:
    movq    $1, %rax
    jmp _eq_end
_eq_end:

    movq    %rbp, %rsp
    popq    %rbp
    ret
main:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $16, %rsp
main_0_entry:
    call    __main
    addq    $0, %rsp
    movq    %rax, -8(%rbp)
    movq    -8(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    jmp main_end
main_end:
    andq   $-16, %rsp
    movq   (stdout), %rdi
    call   fflush
    movq    $60, %rax
    xorq    %rdi, %rdi
    syscall
__iter:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $264, %rsp
__iter_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -96(%rbp)
    movq    24(%rbp),  %rax
    movq    %rax,       -48(%rbp)
    movq    32(%rbp),  %rax
    movq    %rax,       -160(%rbp)
    movq    40(%rbp),  %rax
    movq    %rax,       -240(%rbp)
    movq    48(%rbp),  %rax
    movq    %rax,       -128(%rbp)
    movq    -96(%rbp),  %rax     
    movq    %rax,       -112(%rbp)
    movq    -240(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -128(%rbp),  %rax     
    movq    %rax,       -104(%rbp)
    movq    -48(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    movq    -128(%rbp),  %rax     
    movq    %rax,       -8(%rbp)
    movq    -160(%rbp),  %rax     
    movq    %rax,       -184(%rbp)
    movq    -96(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -240(%rbp),  %rax     
    movq    %rax,       -256(%rbp)
    jmp __iter_1_ifCondBlock
__iter_1_ifCondBlock:
    movq    -112(%rbp), %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $100, 8(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_eq
    pushq   %rax
    malloc  $16
    movq    $1,     (%rax)
    popq    %r9
    movq    %r9,    8(%rax)
    movq    %rax,       -88(%rbp)
    movq   -88(%rbp), %rax
    pushq  %rax
    call   is_bool
    addq  $8, %rsp
    cmpq    $1, %rax
    je      __iter_2_ifBody
    jmp     __iter_3ifExit
__iter_2_ifBody:
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -240(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -128(%rbp),  %rax     
    movq    %rax,       -104(%rbp)
    movq    -48(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    movq    -128(%rbp),  %rax     
    movq    %rax,       -8(%rbp)
    movq    -160(%rbp),  %rax     
    movq    %rax,       -184(%rbp)
    movq    -112(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -240(%rbp),  %rax     
    movq    %rax,       -256(%rbp)
    jmp __iter_3ifExit
__iter_3ifExit:
    movq    -152(%rbp),  %rax
    pushq   %rax
    movq    -152(%rbp),  %rax
    pushq   %rax
    call    __mul
    addq    $16, %rsp
    movq    %rax, -56(%rbp)
    movq    -56(%rbp),  %rax     
    movq    %rax,       -120(%rbp)
    movq    -104(%rbp),  %rax
    pushq   %rax
    movq    -104(%rbp),  %rax
    pushq   %rax
    call    __mul
    addq    $16, %rsp
    movq    %rax, -72(%rbp)
    movq    -72(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -104(%rbp),  %rax     
    movq    %rax,       -104(%rbp)
    movq    -120(%rbp),  %rax     
    movq    %rax,       -32(%rbp)
    movq    -264(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -48(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    movq    -104(%rbp),  %rax     
    movq    %rax,       -8(%rbp)
    movq    -160(%rbp),  %rax     
    movq    %rax,       -184(%rbp)
    movq    -112(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -256(%rbp)
    movq    -120(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -264(%rbp),  %rax     
    movq    %rax,       -80(%rbp)
    jmp __iter_4_ifCondBlock
__iter_4_ifCondBlock:
    movq    -64(%rbp),  %rax
    pushq   %rax
    movq    -32(%rbp),  %rax
    pushq   %rax
    call    __add
    addq    $16, %rsp
    movq    %rax, -248(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $4, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -144(%rbp)
    movq    -248(%rbp), %rax
    pushq   %rax
    movq    -144(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $1, %rax
    je      branch_0
    movq    $0, %rax
    jmp     branch_1
branch_0:
    movq    $1, %rax
branch_1:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -176(%rbp)
    movq   -176(%rbp), %rax
    pushq  %rax
    call   is_bool
    addq  $8, %rsp
    cmpq    $1, %rax
    je      __iter_5_ifBody
    jmp     __iter_6ifExit
__iter_5_ifBody:
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -48(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    movq    -104(%rbp),  %rax     
    movq    %rax,       -8(%rbp)
    movq    -160(%rbp),  %rax     
    movq    %rax,       -184(%rbp)
    movq    -112(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -256(%rbp)
    movq    -32(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -64(%rbp),  %rax     
    movq    %rax,       -80(%rbp)
    jmp __iter_6ifExit
__iter_6ifExit:
    movq    -168(%rbp), %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -232(%rbp)
    movq    -80(%rbp),  %rax
    pushq   %rax
    movq    -136(%rbp),  %rax
    pushq   %rax
    call    __sub
    addq    $16, %rsp
    movq    %rax, -200(%rbp)
    movq    -40(%rbp),  %rax
    pushq   %rax
    movq    -200(%rbp),  %rax
    pushq   %rax
    call    __add
    addq    $16, %rsp
    movq    %rax, -208(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $2, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -224(%rbp)
    movq    -8(%rbp),  %rax
    pushq   %rax
    movq    -256(%rbp),  %rax
    pushq   %rax
    call    __mul
    addq    $16, %rsp
    movq    %rax, -192(%rbp)
    movq    -192(%rbp),  %rax
    pushq   %rax
    movq    -224(%rbp),  %rax
    pushq   %rax
    call    __mul
    addq    $16, %rsp
    movq    %rax, -24(%rbp)
    movq    -184(%rbp),  %rax
    pushq   %rax
    movq    -24(%rbp),  %rax
    pushq   %rax
    call    __add
    addq    $16, %rsp
    movq    %rax, -216(%rbp)
    movq    -216(%rbp),  %rax
    pushq   %rax
    movq    -208(%rbp),  %rax
    pushq   %rax
    movq    -184(%rbp),  %rax
    pushq   %rax
    movq    -40(%rbp),  %rax
    pushq   %rax
    movq    -232(%rbp),  %rax
    pushq   %rax
    call    __iter
    addq    $40, %rsp
    movq    %rax, -16(%rbp)
    movq    -16(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -40(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    movq    -8(%rbp),  %rax     
    movq    %rax,       -8(%rbp)
    movq    -184(%rbp),  %rax     
    movq    %rax,       -184(%rbp)
    movq    -168(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -256(%rbp),  %rax     
    movq    %rax,       -256(%rbp)
    movq    -136(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -80(%rbp),  %rax     
    movq    %rax,       -80(%rbp)
    jmp __iter_end
__iter_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__main:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $616, %rsp
__main_0_entry:
    malloc  $16
    movq    $2, (%rax)
    movq    $-2, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -448(%rbp)
    movq    -448(%rbp),  %rax     
    movq    %rax,       -464(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -472(%rbp)
    movq    -472(%rbp),  %rax     
    movq    %rax,       -176(%rbp)
    movq    -464(%rbp),  %rax
    pushq   %rax
    movq    -176(%rbp),  %rax
    pushq   %rax
    call    __sub
    addq    $16, %rsp
    movq    %rax, -616(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $80, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -536(%rbp)
    movq    -536(%rbp),  %rax
    pushq   %rax
    movq    -616(%rbp),  %rax
    pushq   %rax
    call    __div
    addq    $16, %rsp
    movq    %rax, -296(%rbp)
    movq    -296(%rbp),  %rax     
    movq    %rax,       -184(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $-1, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -568(%rbp)
    movq    -568(%rbp),  %rax     
    movq    %rax,       -576(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -256(%rbp)
    movq    -256(%rbp),  %rax     
    movq    %rax,       -120(%rbp)
    movq    -576(%rbp),  %rax
    pushq   %rax
    movq    -120(%rbp),  %rax
    pushq   %rax
    call    __sub
    addq    $16, %rsp
    movq    %rax, -224(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $40, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -40(%rbp)
    movq    -40(%rbp),  %rax
    pushq   %rax
    movq    -224(%rbp),  %rax
    pushq   %rax
    call    __div
    addq    $16, %rsp
    movq    %rax, -544(%rbp)
    movq    -544(%rbp),  %rax     
    movq    %rax,       -112(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $40, 8(%rax)
    pushq   %rax
    call    __range
    addq    $8, %rsp
    movq    %rax, -32(%rbp)
    movq    -32(%rbp),  %rax
    pushq   %rax
    call    __list
    addq    $8, %rsp
    movq    %rax, -480(%rbp)
    movq    -480(%rbp),  %rax     
    movq    %rax,       -72(%rbp)
    movq    -72(%rbp),  %rax
    pushq   %rax
    call    __len
    addq    $8, %rsp
    movq    %rax, -320(%rbp)
    movq    -320(%rbp),  %rax     
    movq    %rax,       -192(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -64(%rbp)
    movq    -192(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $40, 8(%rax)
    movq    %rax,       -424(%rbp)
    movq    -576(%rbp),  %rax     
    movq    %rax,       -504(%rbp)
    movq    -464(%rbp),  %rax     
    movq    %rax,       -240(%rbp)
    movq    -120(%rbp),  %rax     
    movq    %rax,       -80(%rbp)
    movq    -176(%rbp),  %rax     
    movq    %rax,       -312(%rbp)
    movq    -72(%rbp),  %rax     
    movq    %rax,       -232(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $40, 8(%rax)
    movq    %rax,       -328(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -16(%rbp)
    movq    -72(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -576(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -112(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -464(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -184(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    jmp __main_1_forCondBlock
__main_1_forCondBlock:
    movq    -64(%rbp), %rax
    pushq   %rax
    movq    -608(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $-1, %rax
    je      branch_2
    jmp branch_3
branch_2:
    movq    $1, %rax
    jmp     branch_4
branch_3:
    movq    $0, %rax
    jmp     branch_4
branch_4:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -584(%rbp)
    movq   -584(%rbp), %rax
    pushq  %rax
    call   is_bool
    addq  $8, %rsp
    cmpq    $1, %rax
    je      __main_2forBody
    jmp     __main_forexit_10
__main_2forBody:
    movq    -416(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    -16(%rbp), %rbx
    movq    (%rbx), %rax
    cmpq    $2, %rax
    jne     runtime_panic
    movq    8(%rbx), %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    movq   16(%rax), %rax
    movq    %rax, -200(%rbp)
    movq    -200(%rbp),  %rax     
    movq    %rax,       -552(%rbp)
    movq    -552(%rbp),  %rax
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -272(%rbp)
    movq    -304(%rbp),  %rax
    pushq   %rax
    movq    -272(%rbp),  %rax
    pushq   %rax
    call    __mul
    addq    $16, %rsp
    movq    %rax, -368(%rbp)
    movq    -368(%rbp),  %rax
    pushq   %rax
    movq    -528(%rbp),  %rax
    pushq   %rax
    call    __add
    addq    $16, %rsp
    movq    %rax, -352(%rbp)
    movq    -352(%rbp),  %rax     
    movq    %rax,       -248(%rbp)
    movq    -328(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    pushq   %rax
    movq    $2, %rax
    popq    %rbx
    imulq   %rbx, %rax
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -8(%rbp)
    movq    -8(%rbp),  %rax
    pushq   %rax
    call    __range
    addq    $8, %rsp
    movq    %rax, -160(%rbp)
    movq    -160(%rbp),  %rax
    pushq   %rax
    call    __list
    addq    $8, %rsp
    movq    %rax, -208(%rbp)
    movq    -208(%rbp),  %rax     
    movq    %rax,       -520(%rbp)
    movq    -520(%rbp),  %rax
    pushq   %rax
    call    __len
    addq    $8, %rsp
    movq    %rax, -88(%rbp)
    movq    -88(%rbp),  %rax     
    movq    %rax,       -56(%rbp)
    movq    -16(%rbp), %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -96(%rbp)
    movq    -96(%rbp),  %rax     
    movq    %rax,       -360(%rbp)
    movq    -248(%rbp),  %rax     
    movq    %rax,       -560(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -168(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -608(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    movq    -328(%rbp),  %rax     
    movq    %rax,       -328(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -416(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -528(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -552(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -520(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -304(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -56(%rbp),  %rax     
    movq    %rax,       -440(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -288(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -336(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -128(%rbp)
    movq    -520(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    movq    -464(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -184(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -344(%rbp)
    jmp __main_3_forCondBlock
__main_3_forCondBlock:
    movq    -288(%rbp), %rax
    pushq   %rax
    movq    -440(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $-1, %rax
    je      branch_5
    jmp branch_6
branch_5:
    movq    $1, %rax
    jmp     branch_7
branch_6:
    movq    $0, %rax
    jmp     branch_7
branch_7:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -400(%rbp)
    movq   -400(%rbp), %rax
    pushq  %rax
    call   is_bool
    addq  $8, %rsp
    cmpq    $1, %rax
    je      __main_4forBody
    jmp     __main_forexit_9
__main_4forBody:
    movq    -24(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    -128(%rbp), %rbx
    movq    (%rbx), %rax
    cmpq    $2, %rax
    jne     runtime_panic
    movq    8(%rbx), %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    movq   16(%rax), %rax
    movq    %rax, -432(%rbp)
    movq    -432(%rbp),  %rax     
    movq    %rax,       -408(%rbp)
    movq    -408(%rbp),  %rax
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -392(%rbp)
    movq    -280(%rbp),  %rax
    pushq   %rax
    movq    -392(%rbp),  %rax
    pushq   %rax
    call    __mul
    addq    $16, %rsp
    movq    %rax, -512(%rbp)
    movq    -512(%rbp),  %rax
    pushq   %rax
    movq    -152(%rbp),  %rax
    pushq   %rax
    call    __add
    addq    $16, %rsp
    movq    %rax, -592(%rbp)
    movq    -592(%rbp),  %rax     
    movq    %rax,       -456(%rbp)
    movq    -128(%rbp), %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -104(%rbp)
    movq    -104(%rbp),  %rax     
    movq    %rax,       -144(%rbp)
    movq    -456(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -248(%rbp),  %rax     
    movq    %rax,       -560(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -168(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -608(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    movq    -328(%rbp),  %rax     
    movq    %rax,       -328(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -416(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -528(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -552(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -304(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -440(%rbp),  %rax     
    movq    %rax,       -440(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -288(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -336(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -128(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -280(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    movq    -408(%rbp),  %rax     
    movq    %rax,       -384(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -344(%rbp)
    jmp __main_5_ifCondBlock
__main_5_ifCondBlock:
    movq    -560(%rbp),  %rax
    pushq   %rax
    movq    -136(%rbp),  %rax
    pushq   %rax
    call    __inside
    addq    $16, %rsp
    movq    %rax, -376(%rbp)
    movq   -376(%rbp), %rax
    pushq  %rax
    call   is_bool
    addq  $8, %rsp
    cmpq    $1, %rax
    je      __main_6_ifBody
    jmp     __main_7_elseBlock
__main_6_ifBody:
    movq    -344(%rbp), %rax
    pushq   %rax
    malloc  $17
    movq    $3, (%rax)
    movq    $1, 8(%rax)
    movb    $48, 16(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -488(%rbp)
    movq    -488(%rbp),  %rax     
    movq    %rax,       -600(%rbp)
    movq    -136(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -560(%rbp),  %rax     
    movq    %rax,       -560(%rbp)
    movq    -600(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -608(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    movq    -328(%rbp),  %rax     
    movq    %rax,       -328(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -416(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -528(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -552(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -304(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -440(%rbp),  %rax     
    movq    %rax,       -440(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -288(%rbp)
    movq    -600(%rbp),  %rax     
    movq    %rax,       -336(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -128(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -280(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    movq    -408(%rbp),  %rax     
    movq    %rax,       -384(%rbp)
    movq    -600(%rbp),  %rax     
    movq    %rax,       -344(%rbp)
    jmp __main_8_
__main_7_elseBlock:
    movq    -336(%rbp), %rax
    pushq   %rax
    malloc  $17
    movq    $3, (%rax)
    movq    $1, 8(%rax)
    movb    $49, 16(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -496(%rbp)
    movq    -496(%rbp),  %rax     
    movq    %rax,       -216(%rbp)
    movq    -136(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -560(%rbp),  %rax     
    movq    %rax,       -560(%rbp)
    movq    -216(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -608(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    movq    -328(%rbp),  %rax     
    movq    %rax,       -328(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -416(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -528(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -552(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -304(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -440(%rbp),  %rax     
    movq    %rax,       -440(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -288(%rbp)
    movq    -216(%rbp),  %rax     
    movq    %rax,       -336(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -128(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -280(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    movq    -408(%rbp),  %rax     
    movq    %rax,       -384(%rbp)
    movq    -216(%rbp),  %rax     
    movq    %rax,       -344(%rbp)
    jmp __main_8_
__main_8_:
    movq    -136(%rbp),  %rax     
    movq    %rax,       -136(%rbp)
    movq    -560(%rbp),  %rax     
    movq    %rax,       -560(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -168(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -608(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    movq    -328(%rbp),  %rax     
    movq    %rax,       -328(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -416(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -528(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -552(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -304(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -440(%rbp),  %rax     
    movq    %rax,       -440(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -288(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -336(%rbp)
    movq    -144(%rbp),  %rax     
    movq    %rax,       -128(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    movq    -152(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -280(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    movq    -408(%rbp),  %rax     
    movq    %rax,       -384(%rbp)
    malloc  $16
    movq    $3, (%rax)
    movq    $0, 8(%rax)
    movq    %rax,       -344(%rbp)
    jmp __main_3_forCondBlock
__main_forexit_9:
    movq    -168(%rbp), %rax
    pushq   %rax
    print
    movq    -248(%rbp),  %rax     
    movq    %rax,       -560(%rbp)
    movq    -168(%rbp),  %rax     
    movq    %rax,       -168(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -64(%rbp)
    movq    -608(%rbp),  %rax     
    movq    %rax,       -608(%rbp)
    movq    -328(%rbp),  %rax     
    movq    %rax,       -328(%rbp)
    movq    -360(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -416(%rbp),  %rax     
    movq    %rax,       -416(%rbp)
    movq    -528(%rbp),  %rax     
    movq    %rax,       -528(%rbp)
    movq    -552(%rbp),  %rax     
    movq    %rax,       -264(%rbp)
    movq    -520(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -304(%rbp),  %rax     
    movq    %rax,       -304(%rbp)
    movq    -440(%rbp),  %rax     
    movq    %rax,       -440(%rbp)
    movq    -288(%rbp),  %rax     
    movq    %rax,       -288(%rbp)
    movq    -168(%rbp),  %rax     
    movq    %rax,       -336(%rbp)
    movq    -288(%rbp),  %rax     
    movq    %rax,       -128(%rbp)
    movq    -520(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    movq    -464(%rbp),  %rax     
    movq    %rax,       -152(%rbp)
    movq    -184(%rbp),  %rax     
    movq    %rax,       -280(%rbp)
    movq    -168(%rbp),  %rax     
    movq    %rax,       -344(%rbp)
    jmp __main_1_forCondBlock
__main_forexit_10:
    malloc  $16
    movq    $0, (%rax)
    movq    $0, 8(%rax)
    movq    %rbp, %rsp
    popq    %rbp
    ret
    jmp __main_end
__main_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__sub:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $40, %rsp
__sub_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -8(%rbp)
    movq    24(%rbp),  %rax
    movq    %rax,       -24(%rbp)
    movq    -24(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    pushq   %rax
    movq    -8(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    popq    %rbx
    subq    %rbx, %rax
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -16(%rbp)
    movq    -16(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -8(%rbp),  %rax     
    movq    %rax,       -32(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    jmp __sub_end
__sub_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__of_int:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $24, %rsp
__of_int_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -8(%rbp)
    movq    $8192, %rax
    pushq   %rax
    movq    -8(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    popq    %rbx
    imulq   %rbx, %rax
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -16(%rbp)
    movq    -16(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -8(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    jmp __of_int_end
__of_int_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__mul:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $72, %rsp
__mul_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -40(%rbp)
    movq    24(%rbp),  %rax
    movq    %rax,       -56(%rbp)
    movq    -56(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    pushq   %rax
    movq    -40(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    popq    %rbx
    imulq   %rbx, %rax
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -48(%rbp)
    movq    -48(%rbp),  %rax     
    movq    %rax,       -72(%rbp)
    movq    -72(%rbp), %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $4096, 8(%rax)
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -24(%rbp)
    movq    $8192, %rax
    pushq   %rax
    movq    -24(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    xorq    %rdx,   %rdx
    popq    %rbx
    idivq   %rbx
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -64(%rbp)
    movq    -64(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -40(%rbp),  %rax     
    movq    %rax,       -8(%rbp)
    movq    -72(%rbp),  %rax     
    movq    %rax,       -32(%rbp)
    movq    -56(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    jmp __mul_end
__mul_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__add:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $40, %rsp
__add_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -8(%rbp)
    movq    24(%rbp),  %rax
    movq    %rax,       -24(%rbp)
    movq    -8(%rbp), %rax
    pushq   %rax
    movq    -24(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -16(%rbp)
    movq    -16(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -8(%rbp),  %rax     
    movq    %rax,       -32(%rbp)
    movq    -24(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    jmp __add_end
__add_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__inside:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $56, %rsp
__inside_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -24(%rbp)
    movq    24(%rbp),  %rax
    movq    %rax,       -40(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -32(%rbp)
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    pushq   %rax
    call    __of_int
    addq    $8, %rsp
    movq    %rax, -8(%rbp)
    movq    -8(%rbp),  %rax
    pushq   %rax
    movq    -32(%rbp),  %rax
    pushq   %rax
    movq    -40(%rbp),  %rax
    pushq   %rax
    movq    -24(%rbp),  %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $0, 8(%rax)
    pushq   %rax
    call    __iter
    addq    $40, %rsp
    movq    %rax, -16(%rbp)
    movq    -16(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -24(%rbp),  %rax     
    movq    %rax,       -48(%rbp)
    movq    -40(%rbp),  %rax     
    movq    %rax,       -56(%rbp)
    jmp __inside_end
__inside_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
__div:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $80, %rsp
__div_0_entry:
    movq    16(%rbp),  %rax
    movq    %rax,       -48(%rbp)
    movq    24(%rbp),  %rax
    movq    %rax,       -64(%rbp)
    movq    $8192, %rax
    pushq   %rax
    movq    -48(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    popq    %rbx
    imulq   %rbx, %rax
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -56(%rbp)
    movq    -56(%rbp),  %rax     
    movq    %rax,       -80(%rbp)
    movq    $2, %rax
    pushq   %rax
    movq    -64(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    xorq    %rdx,   %rdx
    popq    %rbx
    idivq   %rbx
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -8(%rbp)
    movq    -80(%rbp), %rax
    pushq   %rax
    movq    -8(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_add
    movq    %rax,       -32(%rbp)
    movq    -64(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    pushq   %rax
    movq    -32(%rbp), %rax
    movq    (%rax), %rcx
    cmpq    $2, %rcx
    jne     runtime_panic
    movq    8(%rax), %rax
    xorq    %rdx,   %rdx
    popq    %rbx
    idivq   %rbx
    pushq   %rax
    malloc  $16
    popq    %r9
    movq    $2,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -72(%rbp)
    movq    -72(%rbp), %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret
    movq    -48(%rbp),  %rax     
    movq    %rax,       -16(%rbp)
    movq    -80(%rbp),  %rax     
    movq    %rax,       -40(%rbp)
    movq    -64(%rbp),  %rax     
    movq    %rax,       -24(%rbp)
    jmp __div_end
__div_end:
    movq   %rbp, %rsp
    popq   %rbp
    ret
