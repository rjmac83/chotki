#include "Bridge.h"
#include "ArtworkImage.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>
#include <qqml.h>

#include <memory>

class ReadingTest final : public QObject {
    Q_OBJECT

    static QQuickItem *findItem(QQuickItem *root, const QString &name) {
        if (!root) return nullptr;
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems()) {
            if (auto *found = findItem(child, name)) return found;
        }
        return nullptr;
    }

    static bool kept(const Bridge *bridge, const QString &title) {
        for (const QVariant &item : bridge->entries()) {
            const QVariantMap map = item.toMap();
            if (map.value("title").toString() == title) return map.value("kept").toBool();
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
        qputenv("CHOTKI_LINUX_REVIEW_DIR", session->directory.path().toUtf8());
        session->bridge = std::make_unique<Bridge>(program, true);
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

    // Place the end mark just inside the bottom of the view, so a later
    // section's end, further down the page, is not in view with it.
    static void revealAtBottom(QQuickItem *scroll, QQuickItem *item) {
        auto *content = scroll->property("contentItem").value<QQuickItem *>();
        const QPointF pos = item->mapToItem(content, QPointF(0, 0));
        const double y = pos.y() - scroll->height() + item->height() + 8;
        scroll->setProperty("contentY", qMax(0.0, y));
    }

    static void click(QQuickWindow *window, QQuickItem *scroll, QQuickItem *item) {
        reveal(scroll, item);
        QTest::qWait(30);
        const QPoint center = item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint();
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center);
    }

    static void wheel(QQuickWindow *window, QQuickItem *item) {
        const QPoint center = item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint();
        QWheelEvent event(QPointF(center), window->mapToGlobal(center), QPoint(), QPoint(0, -120),
                          Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(window, &event);
    }

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void openEachSectionAndFinishTheGospel() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program);
        QVERIFY(session && session->window);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->snapshotReady(), 8000);
        session->bridge->selectDate("2026-10-06");
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->selectedDate(), QString("2026-10-06"), 4000);
        QVERIFY(!kept(session->bridge.get(), "The day's Gospel"));

        QTest::keyClick(session->window, Qt::Key_3, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Reading"));
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->readingReady(), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->readingSections().size() >= 5, 8000);

        QQuickItem *scroll = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((scroll = findItem(session->window->contentItem(), "reading-scroll")), 3000);

        for (int band : {0, 1, 2, 3, 4}) {
            QQuickItem *header = nullptr;
            const QString name = QString("reading-section-%1").arg(band);
            QTRY_VERIFY_WITH_TIMEOUT((header = findItem(session->window->contentItem(), name)), 3000);
            click(session->window, scroll, header);
            if (band == 0) {
                QTest::qWait(70);
                QQuickItem *opening = findItem(session->window->contentItem(), QStringLiteral("reading-shell-0"));
                QVERIFY(opening);
                const double full = opening->property("goal").toDouble();
                QVERIFY(full > 40.0);
                QVERIFY(opening->height() > 2.0);
                QVERIFY(opening->height() < full - 8.0);
            }
            QQuickItem *body = nullptr;
            const QString bodyName = QString("reading-body-%1").arg(band);
            QTRY_VERIFY_WITH_TIMEOUT((body = findItem(session->window->contentItem(), bodyName))
                                     && body->isVisible(), 8000);
            QQuickItem *shell = findItem(session->window->contentItem(),
                                         QString("reading-shell-%1").arg(band));
            QVERIFY(shell);
            QTRY_VERIFY_WITH_TIMEOUT(shell->height() > shell->property("goal").toDouble() - 2.0, 2000);
        }
        QVERIFY(!kept(session->bridge.get(), "The day's Gospel"));
        QVERIFY(!kept(session->bridge.get(), "The day's Epistle"));
        QVERIFY(!kept(session->bridge.get(), "The life of the day's saint"));

        QQuickItem *passage = findItem(session->window->contentItem(), "reading-passage-0");
        QVERIFY(passage);
        const QString text = passage->property("text").toString();
        QVERIFY(text.size() > 40);
        QVERIFY(!text.contains(QChar(0x00B6)));

        bool life = false;
        for (const QVariant &section : session->bridge->readingSections()) {
            const QVariantMap map = section.toMap();
            if (map.value("band").toInt() != 4 || !map.value("open").toBool()) continue;
            const QVariantMap body = map.value("life").toMap();
            QCOMPARE(body.value("license").toString(), QString("CC BY-SA 4.0"));
            QVERIFY(body.value("dates").toString().contains("/"));
            QVERIFY(body.value("licenseNote").toString().contains("unchanged"));
            life = true;
        }
        QVERIFY(life);

        QQuickItem *end = findItem(session->window->contentItem(), "reading-end-0");
        QVERIFY(end);
        revealAtBottom(scroll, end);
        QTest::qWait(50);
        QVERIFY(!kept(session->bridge.get(), "The day's Gospel"));

        wheel(session->window, scroll);
        QTRY_VERIFY_WITH_TIMEOUT(kept(session->bridge.get(), "The day's Gospel"), 4000);
        QVERIFY(!kept(session->bridge.get(), "The day's Epistle"));
        QVERIFY(!kept(session->bridge.get(), "The life of the day's saint"));
    }

    void psalterScrollKeepsTheRule() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program);
        QVERIFY(session && session->window);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->snapshotReady(), 8000);
        session->bridge->selectDate("2026-10-06");
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->selectedDate(), QString("2026-10-06"), 4000);

        QTest::keyClick(session->window, Qt::Key_2, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Prayers"));
        QQuickItem *link = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((link = findItem(session->window->contentItem(), "prayer-psalter"))
                                 && link->isVisible(), 3000);
        const QPoint linkCenter = link->mapToScene(QPointF(link->width() / 2, link->height() / 2)).toPoint();
        QTest::mouseClick(session->window, Qt::LeftButton, Qt::NoModifier, linkCenter);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->psalterReady(), 8000);
        QVERIFY(!session->bridge->psalterAppointed().isEmpty());

        QQuickItem *scroll = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((scroll = findItem(session->window->contentItem(), "psalter-scroll")), 3000);
        QQuickItem *first = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((first = findItem(session->window->contentItem(), "psalter-first")), 3000);
        click(session->window, scroll, first);

        auto appointedOpen = [&]() {
            const QVariantList groups = session->bridge->psalterAppointed();
            if (groups.isEmpty()) return false;
            const QVariantList kathismata = groups.first().toMap().value("kathismata").toList();
            if (kathismata.isEmpty()) return false;
            return kathismata.first().toMap().value("open").toBool();
        };
        QTRY_VERIFY_WITH_TIMEOUT(appointedOpen(), 4000);
        const QVariantMap kathisma = session->bridge->psalterAppointed().first().toMap()
                                         .value("kathismata").toList().first().toMap();
        const int number = kathisma.value("number").toInt();
        QVERIFY(number >= 1 && number <= 20);
        QVERIFY(!kept(session->bridge.get(), "A kathisma of the Psalter"));

        QQuickItem *end = nullptr;
        const QString endName = QString("psalter-end-%1").arg(number);
        QTRY_VERIFY_WITH_TIMEOUT((end = findItem(session->window->contentItem(), endName)), 8000);
        revealAtBottom(scroll, end);
        QTest::qWait(50);
        QVERIFY(!kept(session->bridge.get(), "A kathisma of the Psalter"));

        wheel(session->window, scroll);
        QTRY_VERIFY_WITH_TIMEOUT(kept(session->bridge.get(), "A kathisma of the Psalter"), 4000);
    }
};

QTEST_MAIN(ReadingTest)
#include "ReadingTest.moc"
