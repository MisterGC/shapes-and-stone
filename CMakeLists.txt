# Shapes & Stone - A Minimalist Dungeon Crawler
cmake_minimum_required(VERSION 3.20)

# Include Clayground framework
set(CLAYGROUND_WITH_TOOLS OFF)
set(CLAYGROUND_WITH_EXAMPLES OFF)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../clayground clayground_build)

include(clayapp)

# Images and sounds, loaded relative to the QML ("assets/...") - without them
# in the resources the native app has no cover art, no music and no sound.
file(GLOB SNS_ASSETS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS src/assets/*)

clay_app(shapes_and_stone

    VERSION 0.1

    LINK_LIBS
        Qt::Core
        Qt::Qml
        Qt::Quick

    QML_FILES
        src/Main.qml
        src/Game.qml
        src/Player.qml
        src/Enemy.qml
        src/Wall.qml
        src/WallFace.qml
        src/Torch.qml
        src/Motes.qml
        src/FxParticle.qml
        src/Stain.qml
        src/ExitStairs.qml
        src/Floor.qml
        src/Campfire.qml
        src/Projectile.qml
        src/Npc.qml
        src/DialoguePanel.qml
        src/TitleScreen.qml
        src/MultiplayerLobby.qml
        src/RemotePlayer.qml

    RES_FILES
        ${SNS_ASSETS}
)

# The game's own shaders. PREFIX "/" puts src/shaders/x.frag at
# :/src/shaders/x.frag.qsb - next to the QML in the resources, the same
# relative place the dojo bakes them to beside the sources while developing.
find_package(Qt6 REQUIRED COMPONENTS ShaderTools)
# GLSL 300 es on top of Qt's defaults: the browser draws with WebGL2 and
# refuses to link a fragment shader of another version than its vertex ones.
qt_add_shaders(shapes_and_stone "shapes_and_stone_shaders"
    PREFIX "/"
    GLSL "100 es,120,150,300 es"
    HLSL 50
    MSL 12
    FILES
        src/shaders/floor.frag
        src/shaders/motes.frag
        src/shaders/wall.frag
)
