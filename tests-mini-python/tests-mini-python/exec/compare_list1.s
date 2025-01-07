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
    #xorq    %rdi, %rdi                    # Status 0 (successful exit)
    movq    $1, %rdi
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
main:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $144, %rsp
main_0_entry:

    malloc  $16            
    movq    %rax, -128(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $0,   8(%rax)
    popq    %rax


    malloc  $16            
    movq    %rax, -80(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $0,   8(%rax)
    popq    %rax

    movq    -128(%rbp), %rax
    pushq   %rax
    movq    -80(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $0, %rax
    je      branch_0
    jmp branch_1
branch_0:
    movq    $1, %rax
    jmp     branch_2
branch_1:
    movq    $0, %rax
    jmp     branch_2
branch_2:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -96(%rbp)
    movq    -96(%rbp), %rax
    pushq   %rax
    print

    malloc  $16            
    movq    %rax, -144(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $0,   8(%rax)
    popq    %rax


    malloc  $24            
    movq    %rax, -8(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax

    movq    -144(%rbp), %rax
    pushq   %rax
    movq    -8(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $-1, %rax
    je      branch_3
    jmp branch_4
branch_3:
    movq    $1, %rax
    jmp     branch_5
branch_4:
    movq    $0, %rax
    jmp     branch_5
branch_5:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -32(%rbp)
    movq    -32(%rbp), %rax
    pushq   %rax
    print

    malloc  $24            
    movq    %rax, -112(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax


    malloc  $24            
    movq    %rax, -64(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $2, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax

    movq    -112(%rbp), %rax
    pushq   %rax
    movq    -64(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $0, %rax
    je      branch_6
    jmp branch_7
branch_6:
    movq    $0, %rax
    jmp     branch_8
branch_7:
    movq    $1, %rax
    jmp     branch_8
branch_8:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -72(%rbp)
    movq    -72(%rbp), %rax
    pushq   %rax
    print

    malloc  $32            
    movq    %rax, -88(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $2,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $2, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   24(%rbx)
    popq    %rax


    malloc  $32            
    movq    %rax, -56(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $2,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $4, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    malloc  $16
    movq    $2, (%rax)
    movq    $1, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   24(%rbx)
    popq    %rax

    movq    -88(%rbp), %rax
    pushq   %rax
    movq    -56(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $-1, %rax
    je      branch_9
    jmp branch_10
branch_9:
    movq    $1, %rax
    jmp     branch_11
branch_10:
    movq    $0, %rax
    jmp     branch_11
branch_11:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -40(%rbp)
    movq    -40(%rbp), %rax
    pushq   %rax
    print

    malloc  $24            
    movq    %rax, -48(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $4, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax


    malloc  $32            
    movq    %rax, -24(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $2,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $4, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    malloc  $16
    movq    $2, (%rax)
    movq    $6, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   24(%rbx)
    popq    %rax

    movq    -48(%rbp), %rax
    pushq   %rax
    movq    -24(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $1, %rax
    je      branch_12
    jmp branch_13
branch_12:
    movq    $1, %rax
    jmp     branch_14
branch_13:
    movq    $0, %rax
    jmp     branch_14
branch_14:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -104(%rbp)
    movq    -104(%rbp), %rax
    pushq   %rax
    print

    malloc  $24            
    movq    %rax, -136(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $5, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax


    malloc  $16            
    movq    %rax, -120(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $0,   8(%rax)
    popq    %rax

    movq    -136(%rbp), %rax
    pushq   %rax
    movq    -120(%rbp), %rax
    popq    %rdi
    movq    %rax, %rsi
    call    _builtin_cmp
    cmpq    $1, %rax
    je      branch_15
    jmp branch_16
branch_15:
    movq    $1, %rax
    jmp     branch_17
branch_16:
    movq    $0, %rax
    jmp     branch_17
branch_17:
    pushq  %rax
    malloc  $16
    popq    %r9
    movq    $1,     (%rax)
    movq    %r9,    8(%rax)
    movq    %rax,       -16(%rbp)
    movq    -16(%rbp), %rax
    pushq   %rax
    print
    jmp main_end
main_end:
    andq   $-16, %rsp
    movq   (stdout), %rdi
    call   fflush
    movq    $60, %rax
    xorq    %rdi, %rdi
    syscall
