cmake_minimum_required(VERSION 3.22)
project(ChotkiLinux LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Network Test DBus Widgets)
qt_standard_project_setup()
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.8)
    qt_policy(SET QTP0001 NEW)
endif()

qt_add_executable(chotki-linux main.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
qt_add_qml_module(chotki-linux
    URI ChotkiLinux
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    QML_FILES Main.qml Home.qml Prayers.qml Reading.qml Psalter.qml Library.qml Editor.qml Progress.qml Glossary.qml Settings.qml Onboarding.qml OpeningMark.qml Icon.qml EdgeFade.qml
    RESOURCES fonts/XCharter-Roman.otf fonts/XCharter-Bold.otf
)
set(CHOTKI_APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/../../../ios/Chotki/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
qt_add_resources(chotki-linux "chotki_icon"
    PREFIX "/chotki"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../../../ios/Chotki/Assets.xcassets/AppIcon.appiconset"
    FILES "${CHOTKI_APP_ICON}"
)
target_link_libraries(chotki-linux PRIVATE Qt6::Quick Qt6::Network Qt6::DBus Qt6::Widgets)

enable_testing()
add_executable(chotki-navigation-test tests/NavigationTest.cpp ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-navigation-test PRIVATE Qt6::Quick Qt6::Test)
target_include_directories(chotki-navigation-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-navigation-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME sidebar-navigation COMMAND chotki-navigation-test)
set_tests_properties(sidebar-navigation PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-prayer-rope-test tests/PrayerRopeTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-prayer-rope-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-prayer-rope-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-prayer-rope-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME prayer-rope COMMAND chotki-prayer-rope-test)
set_tests_properties(prayer-rope PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-reading-test tests/ReadingTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-reading-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-reading-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-reading-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME reading COMMAND chotki-reading-test)
set_tests_properties(reading PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-home-actions-test tests/HomeActionsTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-home-actions-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-home-actions-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-home-actions-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME home-actions COMMAND chotki-home-actions-test)
set_tests_properties(home-actions PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-progress-test tests/ProgressTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-progress-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-progress-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-progress-test PRIVATE
    CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml"
    CHOTKI_ARTWORK_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/../../../macos/Sources/Chotki/Resources")
add_test(NAME progress COMMAND chotki-progress-test)
set_tests_properties(progress PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-glossary-test tests/GlossaryTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-glossary-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-glossary-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-glossary-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME glossary COMMAND chotki-glossary-test)
set_tests_properties(glossary PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-library-test tests/LibraryTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-library-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-library-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-library-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME library COMMAND chotki-library-test)
set_tests_properties(library PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-settings-test tests/SettingsTest.cpp Bridge.cpp Bridge.h ArtworkImage.cpp ArtworkImage.h)
target_link_libraries(chotki-settings-test PRIVATE Qt6::Quick Qt6::Test Qt6::DBus)
target_include_directories(chotki-settings-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(chotki-settings-test PRIVATE CHOTKI_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
add_test(NAME settings COMMAND chotki-settings-test)
set_tests_properties(settings PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(chotki-bridge-restart-test tests/BridgeRestartTest.cpp Bridge.cpp Bridge.h)
target_link_libraries(chotki-bridge-restart-test PRIVATE Qt6::Core Qt6::Test Qt6::DBus)
target_include_directories(chotki-bridge-restart-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME bridge-restart COMMAND chotki-bridge-restart-test)
