# Shapes & Stone - A Minimalist Dungeon Crawler
cmake_minimum_required(VERSION 3.20)

# Include Clayground framework
set(CLAYGROUND_WITH_TOOLS OFF)
set(CLAYGROUND_WITH_EXAMPLES OFF)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../clayground clayground_build)

include(clayapp)

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
        src/Floor.qml
)
