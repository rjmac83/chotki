#include "Bridge.h"
#include "Opening.h"
#include "ArtworkImage.h"

#include <QDateTime>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>
#include <qqml.h>

#include <memory>
#include <signal.h>
#include <unistd.h>

class PrayerRopeTest final : public QObject {
    Q_OBJECT

    static QQuickItem *findItem(QQuickItem *root, const QString &name) {
        if (!root) return nullptr;
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems()) {
            if (auto *found = findItem(child, name)) return found;
        }
        return nullptr;
    }

    // The engine is destroyed before the bridge, and the review directory after both.
    struct Session {
        QTemporaryDir directory;
        std::unique_ptr<Bridge> bridge;
        QQmlApplicationEngine engine;
        QQuickWindow *window = nullptr;
    };

    std::unique_ptr<Session> openSession(const QString &program, bool playOpening) {
        auto session = std::make_unique<Session>();
        if (!session->directory.isValid()) return nullptr;
        qputenv("CHOTKI_LINUX_REVIEW_DIR", session->directory.path().toUtf8());
        session->bridge = std::make_unique<Bridge>(program, true);
        session->engine.rootContext()->setContextProperty("bridge", session->bridge.get());
        session->engine.rootContext()->setContextProperty("playOpening", playOpening);
        session->engine.load(QUrl::fromLocalFile(CHOTKI_QML_SOURCE));
        if (session->engine.rootObjects().size() == 1)
            session->window = qobject_cast<QQuickWindow *>(session->engine.rootObjects().first());
        return session;
    }

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void openingDecision() {
        QVERIFY(chotkiReducedMotion("1", "true"));
        QVERIFY(chotkiReducedMotion("true", ""));
        QVERIFY(!chotkiReducedMotion("0", "false"));
        QVERIFY(!chotkiReducedMotion("false", "false"));
        QVERIFY(chotkiReducedMotion("", "false"));
        QVERIFY(chotkiReducedMotion("", "false\n"));
        QVERIFY(chotkiReducedMotion("", "'false'"));
        QVERIFY(!chotkiReducedMotion("", "true"));
        QVERIFY(!chotkiReducedMotion("", ""));
        QVERIFY(chotkiPlaysOpening(false, false));
        QVERIFY(!chotkiPlaysOpening(true, false));
        QVERIFY(!chotkiPlaysOpening(false, true));
        QVERIFY(!chotkiPlaysOpening(true, true));
    }

    void clickRopeReadsCountFromHelper() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program, false);
        QVERIFY(session && session->window);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->snapshotReady(), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->prayerKnots().size() == 33, 8000);

        QTest::keyClick(session->window, Qt::Key_2, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Prayers"));

        QQuickItem *line = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((line = findItem(session->window->contentItem(), "prayer-line")), 3000);
        QVERIFY(line->property("plain").toString().contains(
            "Lord Jesus Christ, Son of God, have mercy on me, a sinner."));

        QQuickItem *rope = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((rope = findItem(session->window->contentItem(), "prayer-rope"))
                                 && rope->width() > 40 && rope->isVisible(), 3000);
        const QPointF center = rope->mapToScene(QPointF(rope->width() / 2, rope->height() / 2));
        QTest::mouseClick(session->window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->prayerCount(), 1, 3000);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->lastPlayed(), QString("tick"), 3000);

        QTest::keyClick(session->window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Home"));
        QTest::keyClick(session->window, Qt::Key_2, Qt::ControlModifier);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Prayers"));
        QCOMPARE(session->bridge->prayerCount(), 1);

        const double base = static_cast<double>(QDateTime::currentSecsSinceEpoch()) + 2.0;
        for (int step = 0; step < 9; ++step) session->bridge->advancePrayerAt(base + step);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->prayerCount(), 10, 3000);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->lastPlayed(), QString("tock"), 3000);
        QCOMPARE(session->bridge->prayerCue(), QString("tock"));

        for (int step = 9; step < 32; ++step) session->bridge->advancePrayerAt(base + step);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->prayerCount(), 33, 3000);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->prayerComplete(), 3000);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->lastPlayed(), QString("bell"), 3000);
        QQuickItem *status = findItem(session->window->contentItem(), "prayer-status");
        QVERIFY(status);
        QCOMPARE(status->property("text").toString(), QString("the knot is complete"));

        const int event = session->bridge->prayerEvent();
        QSignalSpy updates(session->bridge.get(), &Bridge::changed);
        session->bridge->advancePrayerAt(base + 40);
        QTRY_VERIFY_WITH_TIMEOUT(updates.count() > 0, 3000);
        QCOMPARE(session->bridge->prayerCount(), 33);
        QCOMPARE(session->bridge->prayerEvent(), event);

        // The Mac rope still clicks when motion is reduced. Silencing it here
        // would leave a counted knot with no sound.
        const int played = session->bridge->playbackStarts();
        QVERIFY(played >= 1);
        QVariantMap motion;
        motion.insert(QStringLiteral("motion"), true);
        session->bridge->saveSettings(motion);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->reducedMotion(), 8000);
        session->bridge->startAgain();
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->prayerCount(), 0, 3000);
        session->bridge->advancePrayerAt(base + 80);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->prayerCount(), 1, 3000);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->lastPlayed(), QString("tick"), 3000);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->playbackStarts() > played, 3000);
    }

    void openingPlaysOncePerProcess() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        {
            const auto session = openSession(program, true);
            QVERIFY(session && session->window);
            QTRY_COMPARE_WITH_TIMEOUT(session->window->property("openingStarts").toInt(), 1, 8000);
            QQuickItem *mark = nullptr;
            QTRY_VERIFY_WITH_TIMEOUT((mark = findItem(session->window->contentItem(), "opening-mark"))
                                     && mark->isVisible(), 3000);
            QCOMPARE(session->bridge->openingKnots().size(), 11);
            QMetaObject::invokeMethod(session->window, "maybeOpen");
            QCOMPARE(session->window->property("openingStarts").toInt(), 1);

            const qint64 previous = session->bridge->helperProcessId();
            QVERIFY(previous > 0);
            QVERIFY(::kill(static_cast<pid_t>(previous), SIGKILL) == 0);
            QTRY_VERIFY_WITH_TIMEOUT(session->bridge->snapshotReady()
                                     && session->bridge->helperProcessId() != previous, 8000);
            QCOMPARE(session->window->property("openingStarts").toInt(), 1);
        }
        {
            const auto session = openSession(program, true);
            QVERIFY(session && session->window);
            QTRY_COMPARE_WITH_TIMEOUT(session->window->property("openingStarts").toInt(), 1, 8000);
        }
    }

    void reducedMotionSkipsOpening() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program, false);
        QVERIFY(session && session->window);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->openingReady(), 8000);
        QCOMPARE(session->window->property("openingStarts").toInt(), 0);
        QVERIFY(findItem(session->window->contentItem(), "opening-mark") == nullptr);
        QMetaObject::invokeMethod(session->window, "maybeOpen");
        QCOMPARE(session->window->property("openingStarts").toInt(), 0);
    }
};

QTEST_MAIN(PrayerRopeTest)
#include "PrayerRopeTest.moc"
