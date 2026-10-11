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

#include <algorithm>
#include <signal.h>
#include <unistd.h>

class SettingsTest final : public QObject {
    Q_OBJECT

    static QQuickItem *findItem(QQuickItem *root, const QString &name) {
        if (!root) return nullptr;
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems()) {
            if (auto *found = findItem(child, name)) return found;
        }
        return nullptr;
    }

    static bool containsText(QQuickItem *root, const QString &word) {
        if (!root) return false;
        if (root->property("text").toString().contains(word, Qt::CaseInsensitive)) return true;
        for (QQuickItem *child : root->childItems()) {
            if (containsText(child, word)) return true;
        }
        return false;
    }

    static bool centerInView(QQuickItem *scroll, QQuickItem *item) {
        if (!scroll || !item || !item->isVisible()) return false;
        if (item->width() < 2.0 || item->height() < 2.0) return false;
        const QPointF at = item->mapToItem(scroll, QPointF(item->width() / 2.0, item->height() / 2.0));
        return at.x() >= 1.0 && at.y() >= 1.0
            && at.x() <= scroll->width() - 1.0 && at.y() <= scroll->height() - 1.0;
    }

    static void revealY(QQuickItem *scroll, QQuickItem *item) {
        if (!scroll || !item) return;
        const double mid = item->height() > 1.0 ? item->height() / 2.0 : 0.0;
        const double itemY = item->mapToItem(scroll, QPointF(0, mid)).y();
        const double view = scroll->height();
        const double contentY = scroll->property("contentY").toDouble();
        const double limit = std::max(0.0, scroll->property("contentHeight").toDouble() - view);
        const double next = std::clamp(itemY + contentY - std::min(48.0, view / 3.0), 0.0, limit);
        scroll->setProperty("contentY", next);
    }

    static void click(QQuickWindow *window, QQuickItem *item) {
        const double width = std::max(item->width(), item->property("implicitWidth").toDouble());
        const double height = std::max(item->height(), item->property("implicitHeight").toDouble());
        const QPointF local(width > 1.0 ? width / 2.0 : 8.0, height > 1.0 ? height / 2.0 : 8.0);
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, item->mapToScene(local).toPoint());
    }

    static QQuickItem *shown(QQuickWindow *window, const QString &scrollName, const QString &name) {
        QQuickItem *scroll = findItem(window->contentItem(), scrollName);
        QQuickItem *item = findItem(window->contentItem(), name);
        if (!scroll || !item) return nullptr;
        if (!centerInView(scroll, item)) revealY(scroll, item);
        return findItem(window->contentItem(), name);
    }

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void welcomeNamesAChurchAndKeepsReducedMotion() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        QVERIFY2(directory.path().startsWith(QLatin1Char('/')), "The normal record must be an absolute path");
        qputenv("XDG_DATA_HOME", directory.path().toUtf8());

        Bridge bridge(program, false);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("bridge", &bridge);
        engine.rootContext()->setContextProperty("playOpening", false);
        engine.load(QUrl::fromLocalFile(CHOTKI_QML_SOURCE));
        QCOMPARE(engine.rootObjects().size(), 1);
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();

        QTRY_VERIFY_WITH_TIMEOUT(bridge.needsWelcome() && bridge.settingsReady(), 8000);
        QQuickItem *title = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((title = findItem(window->contentItem(), QStringLiteral("welcome-title")))
                                 && title->property("text").toString() == QStringLiteral("Welcome"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(containsText(window->contentItem(),
                                              QStringLiteral("not a substitute for a priest")), 8000);

        QQuickItem *name = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((name = shown(window, QStringLiteral("welcome-scroll"),
                                               QStringLiteral("welcome-name")))
                                 && centerInView(findItem(window->contentItem(), QStringLiteral("welcome-scroll")), name),
                                 3000);
        click(window, name);
        name = findItem(window->contentItem(), QStringLiteral("welcome-name"));
        QVERIFY(name);
        name->forceActiveFocus();
        QVERIFY(name->hasActiveFocus());
        for (const QChar letter : QStringLiteral("Helen"))
            QTest::keyClick(window, letter.toLatin1());
        name = findItem(window->contentItem(), QStringLiteral("welcome-name"));
        QVERIFY(name);
        QCOMPARE(name->property("text").toString(), QStringLiteral("Helen"));

        const QString romanian = QStringLiteral("welcome-church-Romanian Orthodox Church");
        QQuickItem *church = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((church = shown(window, QStringLiteral("welcome-scroll"), romanian))
                                 && centerInView(findItem(window->contentItem(), QStringLiteral("welcome-scroll")), church),
                                 3000);
        click(window, church);

        QQuickItem *next = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((next = shown(window, QStringLiteral("welcome-scroll"),
                                               QStringLiteral("welcome-continue")))
                                 && centerInView(findItem(window->contentItem(), QStringLiteral("welcome-scroll")), next),
                                 3000);
        click(window, next);

        QTRY_VERIFY_WITH_TIMEOUT(!bridge.needsWelcome() && bridge.displayName() == QStringLiteral("Helen"), 8000);
        QQuickItem *heading = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((heading = findItem(window->contentItem(), QStringLiteral("page-title")))
                                 && heading->property("text").toString().contains(QStringLiteral("Helen")), 8000);

        QTest::keyClick(window, Qt::Key_7, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QStringLiteral("Settings"));
        QQuickItem *note = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((note = findItem(window->contentItem(), QStringLiteral("settings-akathist")))
                                 && note->property("text").toString().contains(
                                     QStringLiteral("Orthodox Church in America")), 8000);

        QQuickItem *motion = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((motion = shown(window, QStringLiteral("settings-scroll"),
                                                 QStringLiteral("settings-motion")))
                                 && centerInView(findItem(window->contentItem(), QStringLiteral("settings-scroll")), motion),
                                 3000);
        const int beforeToggle = bridge.motionEvent();
        click(window, motion);
        QTRY_VERIFY_WITH_TIMEOUT(bridge.reducedMotion() && bridge.motionEvent() > beforeToggle, 8000);

        const int recorded = bridge.motionEvent();
        const qint64 previous = bridge.helperProcessId();
        QVERIFY2(previous > 0, "The helper was not running");
        QVERIFY(::kill(static_cast<pid_t>(previous), SIGKILL) == 0);
        QTRY_VERIFY_WITH_TIMEOUT(bridge.snapshotReady() && bridge.helperProcessId() > 0
                                 && bridge.helperProcessId() != previous
                                 && bridge.motionEvent() > recorded
                                 && bridge.reducedMotion(), 8000);
    }
};

QTEST_MAIN(SettingsTest)
#include "SettingsTest.moc"
