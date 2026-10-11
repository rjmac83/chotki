#include "Bridge.h"
#include "ArtworkImage.h"

#include <QDate>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>
#include <qqml.h>

#include <memory>

class LibraryTest final : public QObject {
    Q_OBJECT

    static QQuickItem *findItem(QQuickItem *root, const QString &name) {
        if (!root) return nullptr;
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems()) {
            if (auto *found = findItem(child, name)) return found;
        }
        return nullptr;
    }

    static QString entryField(const Bridge *bridge, const QString &title, const QString &field) {
        for (const QVariant &item : bridge->entries()) {
            const QVariantMap map = item.toMap();
            if (map.value("title").toString() == title) return map.value(field).toString();
        }
        return {};
    }

    static bool showsExactText(QQuickItem *root, const QString &wanted) {
        if (!root || !root->isVisible()) return false;
        if (root->property("text").toString() == wanted) return true;
        for (QQuickItem *child : root->childItems()) {
            if (showsExactText(child, wanted)) return true;
        }
        return false;
    }

    struct Session {
        QTemporaryDir directory;
        std::unique_ptr<Bridge> bridge;
        QQmlApplicationEngine engine;
        QQuickWindow *window = nullptr;
    };

    std::unique_ptr<Session> openSession(const QString &program) {
        auto session = std::make_unique<Session>();
        if (!session->directory.isValid()) return nullptr;
        qputenv("XDG_DATA_HOME", session->directory.path().toUtf8());
        qputenv("XDG_CONFIG_HOME", session->directory.path().toUtf8());
        session->bridge = std::make_unique<Bridge>(program, false);
        session->engine.rootContext()->setContextProperty("bridge", session->bridge.get());
        session->engine.rootContext()->setContextProperty("playOpening", false);
        session->engine.load(QUrl::fromLocalFile(CHOTKI_QML_SOURCE));
        if (session->engine.rootObjects().size() == 1)
            session->window = qobject_cast<QQuickWindow *>(session->engine.rootObjects().first());
        return session;
    }

    static void reveal(QQuickItem *scroll, QQuickItem *item) {
        auto *content = scroll->property("contentItem").value<QQuickItem *>();
        const QPointF pos = item->mapToItem(content, QPointF(0, 0));
        scroll->setProperty("contentY", qMax(0.0, pos.y() - 24));
    }

    static void click(QQuickWindow *window, QQuickItem *scroll, QQuickItem *item) {
        reveal(scroll, item);
        QTest::qWait(30);
        const QPoint center = item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint();
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center);
    }

    static void clickAt(QQuickWindow *window, QQuickItem *item) {
        QTest::qWait(30);
        const QPoint center = item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint();
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center);
    }

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void takeOnTwoRulesThenEditAndPause() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program);
        QVERIFY(session && session->window);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->snapshotReady(), 8000);
        if (session->bridge->needsWelcome()) {
            session->bridge->saveSettings({{QStringLiteral("welcome"), true}});
            QTRY_VERIFY_WITH_TIMEOUT(!session->bridge->needsWelcome(), 8000);
        }
        QVERIFY(session->bridge->entries().isEmpty());

        QQuickItem *add = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((add = findItem(session->window->contentItem(), "home-add-rule"))
                                 && add->isVisible() && add->width() > 0, 3000);
        clickAt(session->window, add);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Library"));
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->libraryReady(), 8000);
        QCOMPARE(session->bridge->libraryPage().value("intro").toString(),
                 QString("Select a prayer, reading, or discipline to add to your routine."));

        QTest::keyClick(session->window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Home"));

        QQuickItem *placard = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((placard = findItem(session->window->contentItem(), "home-add-placard"))
                                 && placard->isVisible() && placard->width() > 0, 3000);
        clickAt(session->window, placard);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Library"));

        QQuickItem *search = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((search = findItem(session->window->contentItem(), "library-search"))
                                 && search->isVisible(), 3000);
        QVERIFY(search->setProperty("text", QString("Morning")));
        QTRY_VERIFY_WITH_TIMEOUT(findItem(session->window->contentItem(), "library-take-morning-prayers")
                                 && !findItem(session->window->contentItem(), "library-take-evening-prayers"),
                                 8000);

        QQuickItem *libraryScroll = findItem(session->window->contentItem(), "library-scroll");
        QVERIFY(libraryScroll);
        click(session->window, libraryScroll,
              findItem(session->window->contentItem(), "library-take-morning-prayers"));
        QQuickItem *title = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((title = findItem(session->window->contentItem(), "editor-title"))
                                 && title->property("text").toString() == QString("Morning prayers"),
                                 8000);
        QQuickItem *editor = findItem(session->window->contentItem(), "editor");
        QVERIFY(editor);
        // The morning template is 06:30. The gate looks for 08:00, so the minute is set as well.
        QVERIFY(editor->setProperty("hour", 7));
        QVERIFY(editor->setProperty("minute", 0));
        QQuickItem *editorScroll = findItem(session->window->contentItem(), "editor-scroll");
        QVERIFY(editorScroll);
        click(session->window, editorScroll, findItem(session->window->contentItem(), "editor-save"));
        QTRY_COMPARE_WITH_TIMEOUT(entryField(session->bridge.get(), "Morning prayers", "time"),
                                  QString("07:00"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(!session->bridge->editorPage().value("open").toBool(), 8000);

        QVERIFY(search->setProperty("text", QString("Evening")));
        QTRY_VERIFY_WITH_TIMEOUT(findItem(session->window->contentItem(), "library-take-evening-prayers")
                                 && !findItem(session->window->contentItem(), "library-take-morning-prayers"),
                                 8000);
        libraryScroll = findItem(session->window->contentItem(), "library-scroll");
        QVERIFY(libraryScroll);
        click(session->window, libraryScroll,
              findItem(session->window->contentItem(), "library-take-evening-prayers"));
        QTRY_VERIFY_WITH_TIMEOUT((title = findItem(session->window->contentItem(), "editor-title"))
                                 && title->property("text").toString() == QString("Evening prayers"),
                                 8000);
        editorScroll = findItem(session->window->contentItem(), "editor-scroll");
        QVERIFY(editorScroll);
        click(session->window, editorScroll, findItem(session->window->contentItem(), "editor-save"));
        QTRY_VERIFY_WITH_TIMEOUT(entryField(session->bridge.get(), "Evening prayers", "time") == QString("21:30")
                                 && entryField(session->bridge.get(), "Morning prayers", "time") == QString("07:00"),
                                 8000);

        QVERIFY(search->setProperty("text", QString("Morning")));
        QTRY_VERIFY_WITH_TIMEOUT((libraryScroll = findItem(session->window->contentItem(), "library-scroll"))
                                 && findItem(session->window->contentItem(), "library-edit-morning-prayers"),
                                 8000);
        click(session->window, libraryScroll,
              findItem(session->window->contentItem(), "library-edit-morning-prayers"));
        QTRY_VERIFY_WITH_TIMEOUT((editor = findItem(session->window->contentItem(), "editor"))
                                 && (title = findItem(session->window->contentItem(), "editor-title"))
                                 && title->property("text").toString() == QString("Morning prayers"),
                                 8000);
        QVERIFY(editor->setProperty("hour", 8));
        QVERIFY(editor->setProperty("minute", 0));
        editorScroll = findItem(session->window->contentItem(), "editor-scroll");
        QVERIFY(editorScroll);
        click(session->window, editorScroll, findItem(session->window->contentItem(), "editor-save"));
        QTRY_COMPARE_WITH_TIMEOUT(entryField(session->bridge.get(), "Morning prayers", "time"),
                                  QString("08:00"), 8000);

        QVERIFY(search->setProperty("text", QString("Evening")));
        QTRY_VERIFY_WITH_TIMEOUT((libraryScroll = findItem(session->window->contentItem(), "library-scroll"))
                                 && findItem(session->window->contentItem(), "library-edit-evening-prayers"),
                                 8000);
        click(session->window, libraryScroll,
              findItem(session->window->contentItem(), "library-edit-evening-prayers"));
        QTRY_VERIFY_WITH_TIMEOUT(findItem(session->window->contentItem(), "editor-pause"), 8000);
        editorScroll = findItem(session->window->contentItem(), "editor-scroll");
        QVERIFY(editorScroll);
        click(session->window, editorScroll, findItem(session->window->contentItem(), "editor-pause"));
        // A pause covers today, inclusive. The next day is where Home shows only the rule left running.
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->entries().size(), 2, 8000);
        QCOMPARE(entryField(session->bridge.get(), "Morning prayers", "time"), QString("08:00"));
        QCOMPARE(entryField(session->bridge.get(), "Evening prayers", "time"), QString("21:30"));

        QTest::keyClick(session->window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Home"));
        QTRY_VERIFY_WITH_TIMEOUT(findItem(session->window->contentItem(), "library") == nullptr, 3000);
        const QDate tomorrow = QDate::fromString(session->bridge->today(), Qt::ISODate).addDays(1);
        QVERIFY(tomorrow.isValid());
        const QString dayName = QString("day-%1").arg(tomorrow.toString(Qt::ISODate));
        QQuickItem *day = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((day = findItem(session->window->contentItem(), dayName))
                                 && day->isVisible() && day->width() > 0, 3000);
        clickAt(session->window, day);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->selectedDate(), tomorrow.toString(Qt::ISODate), 4000);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->entries().size(), 1, 8000);
        QCOMPARE(entryField(session->bridge.get(), "Morning prayers", "time"), QString("08:00"));
        QCOMPARE(entryField(session->bridge.get(), "Evening prayers", "title"), QString());
        QTRY_VERIFY_WITH_TIMEOUT(showsExactText(session->window->contentItem(), "Morning prayers"), 3000);
        QVERIFY(!showsExactText(session->window->contentItem(), "Evening prayers"));
        QVERIFY(showsExactText(session->window->contentItem(), "08:00"));
    }
};

QTEST_MAIN(LibraryTest)
#include "LibraryTest.moc"
