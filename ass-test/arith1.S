.data
    none: .string "None\n"
    true: .string "True\n"
    false: .string "False\n"
    integer: .string "%d\n"
    panic_str: .string "error\n"



.text

.macro malloc size
    subq    $8, %rsp
    movq    \size, (%rsp)
    call my_malloc
    addq    $8, %rsp
.endm

.macro add_any
    popq    %rdi            #lhs
    popq    %rsi            #rhs
    movq    (%rdi), %rcx    #get type
    movq    (%rsi), %rdx    #get type

    cmpq    %rcx, %rdx      #check same type
    jne     runtime_panic   #else panic

    cmpq    $0, %rcx    
    je     runtime_panic   #adding none??
    cmpq    $1, %rcx        
    je      runtime_panic   #adding bool??
    cmpq    $2, %rcx
    je      add_int         
    cmpq    $3, %rcx
    je      runtime_panic   #not implemented
add_int:
    movq    8(%rdi), %rcx
    movq    8(%rsi), %rdx   
    addq    %rcx, %rdx
    pushq   %rdx
    malloc   $16
    popq    %rdx
    movq    $2, (%rax)
    movq    %rdx, 8(%rax)
    pushq   %rax
    jmp     add_end
add_end:

.endm

.globl main
main:
    malloc  $16
    pushq   %rax
    movq    $2, (%rax)
    movq    $21, 8(%rax)  #set the value to 21
    
    malloc  $16
    pushq   %rax 
    movq    $2, (%rax)
    movq    $55, 8(%rax)  #set the value to 55

before_add:
    add_any

    call    print

    
    movq    $60, %rax                 # System call number for `exit`
    xorq    %rdi, %rdi                # Status 0 (successful exit)
    syscall                           # Make the system call






runtime_panic:
    andq $-16, %rsp
    leaq panic_str(%rip), %rdi   # Load address of format string into %rdi
    xorq %rax, %rax         # Set %rax to 0 as required for variadic functions

    call printf             # Call the `printf` function
    movq    $60, %rax                     # System call number for `exit`
    xorq    %rdi, %rdi                    # Status 0 (successful exit)
    syscall                           # Make the system call

allocate_bool_example:
    subq    $8, %rsp
    movq    $16, (%rsp) #set arg0 to 2 bytes
    call    my_malloc
    movq    $1, (%rax)
    movq    $0, 8(%rax)  #set the value to False
    subq    $8, %rsp
    movq    %rax, (%rsp) #save ptr to arg0
    call    print
    addq    $16, %rsp
    ret


allocate_int_example:
    subq    $8, %rsp
    movq    $16, (%rsp) #set arg0 to 2 bytes
    call    my_malloc
    movq    $2, (%rax)
    movq    $21, 8(%rax)  #set the value to 21
    subq    $8, %rsp
    movq    %rax, (%rsp) #save ptr to arg0
    call    print
    addq    $16, %rsp
    ret

allocate_none_example:
    subq    $8, %rsp
    movq    $16, (%rsp)     # set my_malloc arg0 to 16
    call    my_malloc
    movq    $0, (%rax)
    movq    $0, 8(%rax)

    subq    $8, %rsp        # prepare call print args
    movq    %rax, (%rsp)
    call    print
    addq    $16, %rsp
    ret

# We allocate a "hello\0" here , which length is 6.
allocate_str_example:
    subq    $8, %rsp
    movq    $64, (%rsp)     # set my_malloc arg0 to (6 + 2) * 8, 2 additional 8 bytes, one for type , one for length
    call    my_malloc

    movq    $3, (%rax)      # set the type
    movq    $6, 8(%rax)     # set the length
    movq    $104, 16(%rax)   # set the str contents
    movq    $104, 24(%rax)
    movq    $104, 32(%rax)
    movq    $104, 40(%rax)
    movq    $104, 48(%rax)
    movq    $0, 56(%rax)

    subq    $8, %rsp        # call print
    movq    %rax, (%rsp)
    call    print
    addq    $16, %rsp
    ret

print:
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
print_end:
    addq    $8,  %rsp
    movq    %rbp, %rsp
    popq    %rbp
    ret

call_print_none:
    call    print_none
    jmp print_end
call_print_bool:
    call    print_bool
    jmp print_end
call_print_int:
    call    print_int
    jmp print_end
call_print_str:
    call    print_string
    jmp print_end

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
    subq    $8, %rsp
    movq    $10,(%rsp)
    call    my_putchar
    addq    $8, %rsp

    movq    %rbp, %rsp
    popq    %rbp
    ret 
    
    subq    $8, %rsp
    movq    %rsi, (%rsp)
    call    my_putchar
    subq    $8, %rsp
    movq    $10,(%rsp)
    call    my_putchar

    addq    $16, %rsp

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

my_malloc:
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    movq    16(%rbp), %rdi
    call    malloc
    movq    %rbp, %rsp
    popq    %rbp
    ret