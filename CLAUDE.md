# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PuTTY is a free SSH, Telnet, and serial terminal emulator for Windows and Unix. The codebase is organized around a clean separation between platform-independent protocol/terminal logic and platform-specific UI and system integration.

## Build System

### Generating Makefiles

**Never edit Makefiles directly.** All Makefiles are generated from the `Recipe` file.

To regenerate Makefiles after changing `Recipe`:
```bash
./mkfiles.pl
```

For Unix autoconf/automake builds:
```bash
./mkfiles.pl && ./mkauto.sh
```

### Building on Unix

Using autoconf (recommended):
```bash
cd unix
./configure
make
```

Or from the top-level directory:
```bash
./configure  # wrapper that calls unix/configure
make
```

Building only command-line tools (no GTK):
```bash
cd unix
./configure --without-gtk
make
```

Selecting GTK version (1.2, 2.0, or 3.0):
```bash
./configure --with-gtk=3
```

### Building on Windows

Change to the `windows` subdirectory for all builds.

Visual Studio (command-line):
```bash
cd windows
nmake -f Makefile.vc
```

MinGW/Cygwin:
```bash
cd windows
make -f Makefile.mgw
```

Borland C:
```bash
cd windows
make -f Makefile.bor
```

### Compile-Time Options

Options are set via the `COMPAT` and `XFLAGS` variables. See comments in `Recipe` for full list.

Common options:
- `XFLAGS=/DDEBUG` - Enable internal debugging
- `XFLAGS=/DFUZZING` - Build for fuzz testing (insecure, for testing only)
- `COMPAT=/DNO_GSSAPI` - Disable GSSAPI support
- `COMPAT=/DNO_IPV6` - Disable IPv6 support

Example:
```bash
nmake -f Makefile.vc XFLAGS=/DDEBUG
```

### Testing

Build and run the bignum test:
```bash
# On Unix
make testbn
./testbn < testdata/bignumtests.txt

# On Windows
nmake -f Makefile.vc testbn.exe
testbn.exe < testdata/bignumtests.txt
```

## Architecture

### Core Design Principles

1. **Platform Independence**: All protocol, cryptographic, and terminal logic lives in the root directory and is platform-agnostic
2. **Platform Abstraction**: Platform-specific code in `windows/` and `unix/` implements well-defined interfaces from headers like `storage.h`, `network.h`
3. **Component Isolation**: Backend (protocol), Terminal (emulation), Frontend (GUI), and Ldisc (line discipline) are separate with clear interfaces

### Directory Structure

- Root directory: Platform-independent core (SSH, terminal, crypto, config)
- `windows/`: Windows-specific implementations (Win32 GUI, Windows networking, Registry storage)
- `unix/`: Unix-specific implementations (GTK GUI, Unix networking, file storage)
- `charset/`: Character set conversion libraries
- `doc/`: Documentation in Halibut format
- `testdata/`: Test data files

### Key Components

#### Backend System (Protocol Layer)

Located in root directory: `ssh.c` (11K+ lines), `telnet.c`, `raw.c`, `rlogin.c`

Backends use a vtable pattern defined in `putty.h`:
```c
struct backend_tag {
    const char *name;
    int (*init)(...);
    void (*send)(...);
    // ... function pointers for protocol operations
};
```

Backend selection arrays in `be_*.c` files:
- `be_all.c` - All backends (SSH, Telnet, Raw, Rlogin, Serial)
- `be_ssh.c` - SSH only
- `be_nossh.c` - All except SSH
- `be_none.c` - No backends (for pterm)

#### Terminal Emulator

Located in `terminal.c` (6,500+ lines), `terminal.h`

Self-contained VT100/xterm emulator with:
- Screen buffer using tree234 (balanced binary trees) for scrollback
- Complex attribute system (TATTR, ATTR, LATTR, DATTR) for text styling
- Full Unicode and combining character support
- Escape sequence state machine

The Terminal structure (325+ lines in terminal.h) contains all terminal state.

#### Line Discipline (Ldisc)

Located in `ldisc.c`, `ldiscucs.c`

Mediates between Terminal and Backend, handling:
- Local echo
- Line editing
- Protocol-specific character handling

Bridges terminal, backend, and frontend:
```c
struct ldisc_tag {
    Terminal *term;
    Backend *back;
    void *backhandle;
    void *frontend;
};
```

#### Configuration System

Located in `conf.c`, `settings.c`

Tree-based key-value store using tree234:
- Keys are CONF_* enumerated constants
- Values can be int, string, Filename, or FontSpec
- Platform-specific persistence via storage.h interface

Configuration UI defined platform-independently in `config.c` (2,700+ lines) using the dialog framework from `dialog.h`.

#### Network Abstraction

Located in `network.h`, platform implementations in `windows/winnet.c` and `unix/uxnet.c`

Plug/Socket pattern:
- **Socket**: Network connection with operations (write, close, etc.)
- **Plug**: Consumer of network data with callbacks (receive, closing, etc.)

Same SSH code works on both Windows sockets and Unix file descriptors.

#### Dialog Framework

Located in `dialog.h`, `dialog.c`

Platform-independent dialog specification that:
- Defines controls abstractly (CTRL_EDITBOX, CTRL_CHECKBOX, etc.)
- Uses handler functions with events (EVENT_VALCHANGE, EVENT_ACTION)
- Renders in platform code (`windows/windlg.c`, `unix/gtkdlg.c`)

### Data Flow

**Typical SSH connection flow:**
1. Frontend creates Backend via `backend->init()`
2. Backend creates Socket via platform networking
3. Socket receives data, calls Backend's Plug callbacks
4. Backend processes SSH protocol, decrypts
5. Backend calls `from_backend(frontend, data, len)`
6. Frontend passes to Terminal via `term_data()`
7. Terminal processes escape sequences, updates screen buffer
8. Terminal calls Frontend drawing callbacks
9. User input: Frontend calls `ldisc_send()`
10. Ldisc processes, sends to Backend
11. Backend encrypts, sends via Socket

### Common Patterns

**Callback Queue** (`callback.c`): Deferred callback queue to avoid reentrancy
```c
void queue_toplevel_callback(toplevel_callback_fn_t fn, void *ctx);
void run_toplevel_callbacks(void);
```

**Tree234** (`tree234.c`): Balanced binary tree used throughout for:
- Terminal scrollback buffer
- Configuration storage
- Session management

**Event Loop**: Platform-specific (`windows/window.c`, `unix/gtkwin.c`) drives all activity:
- Network events (socket ready)
- User input
- Timer callbacks
- Deferred callbacks

## Important Files

### Must-Read Headers
- `putty.h` - Core type definitions, global interfaces, Terminal/Backend structures
- `ssh.h` - SSH protocol structures and constants
- `terminal.h` - Terminal structure and interfaces
- `network.h` - Network abstraction (Socket/Plug)
- `storage.h` - Configuration persistence interface
- `dialog.h` - Dialog/config UI framework

### Build System
- `Recipe` - **Single source of truth** for what gets built and how
- `mkfiles.pl` - Perl script that generates all Makefiles from Recipe
- `configure.ac` - Autoconf configuration for Unix builds
- `mkauto.sh` - Generates Unix configure script from configure.ac

### Platform Entry Points
- `windows/window.c` - Windows GUI main window (WinMain, window procedure)
- `windows/wincons.c` - Windows console UI (for plink, pscp, psftp)
- `unix/gtkwin.c` - GTK GUI main window
- `unix/uxcons.c` - Unix console UI

## Development Workflow

### Adding a New Feature

1. Understand which layer needs changes (backend vs terminal vs frontend)
2. For platform-independent changes: edit files in root directory
3. For platform-specific changes: edit both `windows/` and `unix/` files to maintain parity
4. Update `Recipe` if adding new source files or changing program dependencies
5. Run `./mkfiles.pl` to regenerate Makefiles
6. Build and test on target platforms

### Adding a New Program

1. Edit `Recipe` to define the program:
   ```
   newprog : [U] source1 source2 MODULE1 MODULE2
   ```
   - `[G]` = Windows GUI, `[C]` = Windows Console, `[X]` = Unix GTK, `[U]` = Unix command-line
2. Define object modules if needed (groups of related .c files)
3. Run `./mkfiles.pl`
4. Build normally

### Working with SSH Code

The SSH implementation in `ssh.c` is a large state machine:
- SSH-1 and SSH-2 protocol support
- Packet handling with sequence numbers and MAC verification
- Key exchange, authentication, channel management
- Data encryption/decryption

Related files:
- `ssh*.c` - Cryptographic primitives (AES, DES, RSA, DSA, ECC, SHA, etc.)
- `sshbn.c` - Big number arithmetic
- `sshpubk.c` - Public key operations
- `sshshare.c` - SSH connection sharing

### Working with Terminal Code

Terminal emulator maintains multiple buffers:
- Primary screen
- Alternate screen (for full-screen apps)
- Scrollback

Screen cells contain:
- Character code (with Unicode support)
- Attributes (color, bold, underline, etc.)
- Combining characters (linked list for multi-codepoint graphemes)

To modify terminal behavior:
1. Check `terminal.c` for escape sequence handling
2. Look at `term_data()` for character input processing
3. See `term_paint()` for rendering logic
4. Update `terminal.h` if adding terminal state

### Cross-Platform Considerations

When adding features that touch platform-specific code:
1. Implement in `windows/` for Windows
2. Implement in `unix/` for Unix
3. Use existing patterns (see how similar features are implemented)
4. Test on both platforms if possible

Storage example:
- Registry on Windows (`windows/winstore.c`)
- Files in ~/.putty on Unix (`unix/uxstore.c`)
- Both implement `storage.h` interface

## Documentation

Documentation is written in Halibut format (`.but` files) in the `doc/` directory.

To build documentation (requires Halibut from http://www.chiark.greenend.org.uk/~sgtatham/halibut/):
```bash
cd doc
make
```

This generates Windows Help files, Unix man pages, HTML, and other formats.

## Code Style

- Indentation: Mixed tabs and spaces (follow existing style in each file)
- Brace style: K&R style (opening brace on same line)
- Naming: Lower case with underscores (snake_case)
- Comments: C-style `/* */` throughout

## Source Control

This is a Git repository. The main branch is `master`.

When making commits, follow the existing commit message style (check `git log` for examples).
