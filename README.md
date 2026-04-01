# Constellation Memories

A beautiful LÖVE2D application for creating, viewing, and cherishing digital memories arranged as an interactive star constellation. A poetic way to capture moments and revisit them through a celestial interface.

## Features

### Core Experience
- **Memory Creation** - Create new memories with titles, descriptions, and optional images
- **Star Constellation UI** - Browse memories arranged as interactive star constellations
- **Image Storage** - Seamlessly import and manage images for memories
- **Persistent Storage** - All memories are saved locally using LÖVE's filesystem
- **Smooth Animations** - Fluid transitions and elegant visual effects

### Visual Effects
- **Ambient Star Field** - Falling stars and particle effects in the background
- **Startup Animation** - Beautiful introductory sequence with star arc and text reveal
- **Shader System** - Galaxy shaders and haze effects for atmospheric visuals
- **Post-Processing** - Multiple visual filters (bloom, glow, desaturation, etc.)
- **Responsive UI** - Smooth scaling and adaptive layout

### Technical Features
- **Flux Tweening** - Smooth animation library for motion and transitions
- **Moonshine Effects** - Comprehensive post-processing and visual effects
- **Native Filesystem** - Direct file system access for image importing
- **Performance Optimized** - Efficient particle rendering and batching
- **Autobatch Support** - Optional GPU optimization layer

## Project Structure

```
constellation-memories-love2d/
├── main.lua              # Application entry point and event loop
├── conf.lua              # LÖVE configuration
├── startup.lua           # Splash screen and title animation
├── star_map.lua          # Main constellation UI and navigation
├── memory_store.lua      # Memory data persistence layer
├── media_store.lua       # Image import and file handling
│
├── ui/                   # User interface components
│   ├── ui.lua           # Main UI state and management
│   ├── composer.lua      # Memory editor/creator
│   ├── viewer.lua        # Memory view panel
│   ├── textedit.lua      # Text input component
│   ├── simple_picker.lua # Image picker
│   └── common.lua        # Shared UI utilities
│
├── core/                 # Core systems
│   ├── config.lua        # Application configuration
│   ├── colors.lua        # Color palette and themes
│   └── utils.lua         # Utility functions
│
├── systems/              # Major systems
│   ├── background.lua    # Background rendering
│   ├── falling.lua       # Particle/falling star system
│   └── links.lua         # Memory connections/links
│
├── stars/                # Star constellation rendering
│   ├── classes.lua       # Star entity classes
│   ├── particles.lua     # Star particle effects
│   └── render.lua        # Star rendering pipeline
│
├── fx/                   # Effects and filters
│   ├── postfx.lua        # Post-processing pipeline
│   ├── presets.lua       # Effect presets and configurations
│   └── (shader files)    # Custom shaders
│
├── shaders/              # GLSL shader code
│   ├── galaxy.lua        # Galaxy shader implementation
│   └── haze.glsl         # Haze effect shader
│
├── data/                 # Data schemas and formats
│   ├── memory_schema.lua # Memory data structure definition
│   └── memories.lua      # Persisted memory data
│
├── libs/                 # External libraries
│   ├── flux.lua          # Tweening library
│   ├── moonshine/        # Post-processing effects
│   └── nativefs.lua      # Native filesystem access
│
├── assets/               # Game assets
│   ├── icon.png/.ico     # Application icon
│   ├── font.ttf          # Primary font
│   └── (font files)      # Additional fonts
│
└── perf.lua              # Performance profiling tools
```

## Getting Started

### Requirements
- LÖVE 2D 11.4+ (https://love2d.org/)
- Lua 5.1+ (included with LÖVE)

### Running the Application

**From Source:**
```bash
cd constellation-memories-love2d
love .
```

**From Built Package:**
- Windows: Run `constellation-memories.exe`
- Mac/Linux: Use the LÖVE application bundle

### Building a Distributable

**Create a .love file (cross-platform):**
```bash
# From project root, zip all files
zip -r constellation-memories.love *

# Run with LÖVE
love constellation-memories.love
```

**Create a Windows Executable:**
```bash
# Concatenate fused executable with .love file
copy /b love.exe + constellation-memories.love constellation-memories.exe
```

## How It Works

### Memory Creation Flow
1. **Composer opens** - Click "New Memory" button
2. **Add content** - Enter title, description, and optionally select an image
3. **Save** - Memory is persisted locally with embedded image data
4. **Added to constellation** - New memory appears in the star map

### Navigation
- **Mouse interaction** - Click and drag stars to rearrange
- **Zoom and pan** - Scroll to zoom, drag to pan the star field
- **Peek preview** - Hover over stars for memory preview
- **View details** - Click a star to open the full memory viewer

### Data Persistence
- Memories stored in LÖVE's `love.filesystem` directory
- Location: `%AppData%/LOVE/constellation-memories/` (Windows)
- Images embedded as base64 in memory data files
- Automatic save on every change

## Development

### Code Style
- Lua follows idiomatic patterns with clear naming
- Module-based architecture for maintainability
- Separation of concerns (UI, rendering, data storage)
- Minimal external dependencies (only essential libraries)

### Key Libraries
- **Flux** - Smooth animations and tweening
- **Moonshine** - Post-processing and visual effects
- **NativeFS** - File system access for image importing

### Adding New Effects
1. Create effect module in `fx/presets.lua`
2. Register shader in `libs/moonshine_register.lua`
3. Activate in UI effect selector

## Performance Considerations

- Particle system optimized for 60fps on modest hardware
- Shader effects can be toggled for lower-end systems
- Autobatch mode automatically batches draw calls
- Star rendering uses spatial optimization
- Image data compressed where possible

## Future Enhancements

- Export memories as images or PDF
- Share memory constellations with others
- Themes and customization options
- Memory timeline view
- Integration with cloud storage
- Collaborative memory creation

## License

This is a personal creative project. Feel free to use it as inspiration or learn from the code!

## Credits

Built with:
- LÖVE 2D framework
- Flux tweening library
- Moonshine post-processing effects
- Various open-source fonts and assets
