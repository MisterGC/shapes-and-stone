# Shapes & Stone - A Minimalist Dungeon Crawler
cmake_minimum_required(VERSION 3.20)

# clay_app() registers the headless start check "testshapes_and_stone"
# (QT_QPA_PLATFORM=minimal, any QML warning fails it); ctest only sees it
# with testing enabled here at the top.
enable_testing()

# Include Clayground framework - the submodule at clayground/ pins the commit
# the game builds against; moving the submodule is how to change it.
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/clayground/CMakeLists.txt)
    message(FATAL_ERROR "Clayground submodule missing - run: git submodule update --init --recursive")
endif()
set(CLAYGROUND_WITH_TOOLS OFF)
set(CLAYGROUND_WITH_EXAMPLES OFF)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/clayground clayground_build)

include(clayapp)

# The balance table is one object every file reads (Balance.knight.hp, ...).
# The files are looked up from their own directory, :/src, so the qmldir that
# declares the singleton goes into the resources beside them.
set_source_files_properties(src/Balance.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

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
        src/Balance.qml
        src/Game.qml
        src/Player.qml
        src/KnightView.qml
        src/Enemy.qml
        src/Wall.qml
        src/WallFace.qml
        src/Torch.qml
        src/Motes.qml
        src/FxParticle.qml
        src/Stain.qml
        src/BodyShade.qml
        src/ExitStairs.qml
        src/Floor.qml
        src/Campfire.qml
        src/Projectile.qml
        src/Npc.qml
        src/DialoguePanel.qml
        src/TitleScreen.qml
        src/FallenScreen.qml
        src/MultiplayerLobby.qml
        src/RemotePlayer.qml
        src/Session.qml

    RES_FILES
        src/qmldir
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
        src/shaders/body.frag
        src/shaders/floor.frag
        src/shaders/motes.frag
        src/shaders/wall.frag
)
