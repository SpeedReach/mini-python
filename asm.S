.data
    none: .string "None"
    true: .string "True"
    false: .string "False"
    integer: .string "%d"
    panic_str: .string "error\n"
.bss
    a: .zero 8
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
    imulq   $8, %rcx                # Since every char is 8 bytes in mini-python, we have to * 8
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

print_next_line:
    subq    $8, %rsp
    movq    $10, (%rsp)
    call    my_putchar
    addq    $8, %rsp
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
    xorq    %rdi, %rdi                    # Status 0 (successful exit)
    syscall                           # Make the system call

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
add_list:
main:
    pushq  %rbp
    movq    %rsp, %rbp
    subq    $80, %rsp
main_0_entry:

    malloc  $24            
    movq    %rax, -48(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    malloc  $16
    movq    $2, (%rax)
    movq    $3, 8(%rax)
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax


    malloc  $24            
    movq    %rax, -8(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    movq    -48(%rbp),  %rax 
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax


    malloc  $24            
    movq    %rax, -24(%rbp)
    pushq   %rax           
    movq    $4,     (%rax)
    movq    $1,   8(%rax)
    movq    -8(%rbp),  %rax 
    movq    (%rsp), %rbx
    movq    %rax,   16(%rbx)
    popq    %rax

    movq    -24(%rbp), %rax
    movq    %rax, (a)
    movq    (a), %rax
    movq    %rax, -64(%rbp)
    movq    -64(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    $0, %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    movq   16(%rax), %rax
    movq    %rax, -32(%rbp)
    movq    -32(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    $0, %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    movq   16(%rax), %rax
    movq    %rax, -56(%rbp)
    movq    -56(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    $0, %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    addq    $16, %rax
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $6, 8(%rax)
    popq   %rbx
    movq    %rax, (%rbx)
    movq    -56(%rbp),  %rax
    movq    %rax, -40(%rbp)
    movq    -32(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    $0, %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    addq    $16, %rax
    pushq   %rax
    movq    -40(%rbp), %rax
    popq   %rbx
    movq    %rax, (%rbx)
    movq    -32(%rbp),  %rax
    movq    %rax, -72(%rbp)
    movq    -64(%rbp),  %rax
    pushq   %rax
    movq    (%rax), %rax
    cmpq    $4, %rax
    jne     runtime_panic
    movq    $0, %rbx
    popq    %rax
    movq    8(%rax), %rcx
    cmpq    %rcx, %rbx
    jge     runtime_panic
    imul    $8, %rbx
    addq    %rbx, %rax
    addq    $16, %rax
    pushq   %rax
    movq    -72(%rbp), %rax
    popq   %rbx
    movq    %rax, (%rbx)
    movq    -64(%rbp),  %rax
    movq    %rax, -80(%rbp)
    movq    -80(%rbp), %rax
    movq    %rax, (a)
    movq    (a), %rax
    movq    %rax, -16(%rbp)
    movq    -16(%rbp), %rax
    pushq   %rax
    print
    jmp main_end
main_end:
    movq    $60, %rax
    xorq    %rdi, %rdi
    syscall
