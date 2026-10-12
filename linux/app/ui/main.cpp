#include "Bridge.h"
#include "ArtworkImage.h"
#include "Opening.h"

#include <QApplication>
#include <QAction>
#include <QDir>
#include <QIcon>
#include <QKeySequence>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QSystemTrayIcon>
#include <QLockFile>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <qqml.h>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>

#include <functional>
#include <memory>

#include <unistd.h>

int main(int argc, char *argv[]) {
    QApplication application(argc, argv);
    application.setApplicationName("Chotki");
    application.setDesktopFileName("org.chotki.Chotki");
    const QIcon chotkiIcon(QStringLiteral(":/chotki/icon-1024.png"));
    if (!chotkiIcon.isNull()) application.setWindowIcon(chotkiIcon);

    const QStringList arguments = application.arguments();
    const bool screenshot = arguments.size() == 5 && arguments.at(3) == "--screenshot";
    if (arguments.size() < 3 || (!screenshot && arguments.size() != 3) ||
        (arguments.at(1) != "--review" && arguments.at(1) != "--normal") ||
        (screenshot && arguments.at(1) != "--review")) {
        qCritical("Usage: chotki-linux --review|--normal /path/to/ChotkiLinuxBridge [--screenshot /path/to/review.png]");
        return 2;
    }
    const bool review = arguments.at(1) == "--review";
    const QString serverName = QString("org.chotki.linux.%1.%2")
        .arg(getuid()).arg(review ? "review" : "normal");

    const auto activateExisting = [&](QLocalSocket &socket) {
        if (screenshot) {
            qCritical("A review window is already open, so the screenshot was not taken");
            return 8;
        }
        socket.write("activate\n");
        socket.waitForBytesWritten(250);
        return 0;
    };

    QLocalSocket existing;
    existing.connectToServer(serverName);
    if (existing.waitForConnected(250)) return activateExisting(existing);

    // Only the process holding this lock may remove a stale socket. A second
    // launch must never unlink the first launch's live socket.
    const QString lockPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
        + QDir::separator() + serverName + ".lock";
    QLockFile lock(lockPath);
    if (!lock.tryLock(0)) {
        existing.connectToServer(serverName);
        if (existing.waitForConnected(1000)) return activateExisting(existing);
        qCritical("Another Chotki instance is starting but cannot be reached");
        return 3;
    }
    QLocalServer::removeServer(serverName);
    QLocalServer server;
    if (!server.listen(serverName)) {
        qCritical("Cannot establish Chotki's single-instance socket");
        return 3;
    }

    Bridge bridge(arguments.at(2), review);
    qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    QString animations;
    if (!screenshot && qEnvironmentVariable("CHOTKI_REDUCE_MOTION").isEmpty()) {
        QProcess desktop;
        desktop.start("gsettings", {"get", "org.gnome.desktop.interface", "enable-animations"});
        if (desktop.waitForFinished(200))
            animations = QString::fromUtf8(desktop.readAllStandardOutput());
    }
    const bool playOpening = chotkiPlaysOpening(
        chotkiReducedMotion(qEnvironmentVariable("CHOTKI_REDUCE_MOTION"), animations), screenshot);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty("playOpening", playOpening);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/ChotkiLinux/Main.qml")));
    if (engine.rootObjects().isEmpty()) return 4;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) return 5;
    if (!chotkiIcon.isNull()) {
        window->setIcon(chotkiIcon);
        window->setProperty("iconSource", QStringLiteral("qrc:/chotki/icon-1024.png"));
    }
    if (screenshot) {
        const QString path = arguments.at(4);
        auto *timer = new QTimer(window);
        auto attempts = std::make_shared<int>(0);
        timer->setInterval(100);
        QObject::connect(timer, &QTimer::timeout, window, [window, path, timer, attempts, &application, &bridge] {
            if (!bridge.snapshotReady()) {
                if (++(*attempts) < 80) return;
                qCritical("The Swift record did not load before the review screenshot");
                application.exit(7);
                return;
            }
            timer->stop();
            const bool saved = window->grabWindow().save(path);
            if (!saved) {
                qCritical("Could not save the review screenshot");
                application.exit(6);
                return;
            }
            const QString pages = qEnvironmentVariable("CHOTKI_REVIEW_PAGES");
            if (pages.isEmpty()) {
                application.exit(0);
                return;
            }
            QDir().mkpath(pages);
            const QStringList sections = {
                QStringLiteral("Prayers"), QStringLiteral("Reading"), QStringLiteral("Library"),
                QStringLiteral("Progress"), QStringLiteral("Glossary"), QStringLiteral("Settings")
            };
            auto index = std::make_shared<int>(0);
            auto step = std::make_shared<std::function<void()>>();
            *step = [window, pages, sections, index, step, &application, &bridge] {
                if (*index >= sections.size()) {
                    application.exit(0);
                    return;
                }
                const QString section = sections.at(*index);
                if (section == QLatin1String("Reading")) bridge.showReading();
                if (section == QLatin1String("Glossary")) bridge.showGlossary(QString(), QString());
                window->setProperty("section", section);
                const QString file = pages + QLatin1Char('/') + section.toLower() + QStringLiteral(".png");
                QTimer::singleShot(700, window, [window, file, index, step, &application] {
                    if (!window->grabWindow().save(file)) {
                        qCritical("Could not save a review page");
                        application.exit(6);
                        return;
                    }
                    ++(*index);
                    (*step)();
                });
            };
            (*step)();
        });
        timer->start();
    }
    QObject::connect(&server, &QLocalServer::newConnection, window, [&server, window] {
        while (QLocalSocket *socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            socket->disconnectFromServer();
            window->show();
            window->raise();
            window->requestActivate();
        }
    });
    // A shell with no tray leaves the window exactly as it is. The tray never
    // hides that window, and a review screenshot does not add one.
    if (!screenshot && QSystemTrayIcon::isSystemTrayAvailable()) {
        auto *tray = new QSystemTrayIcon(&application);
        QPixmap mark(22, 22);
        mark.fill(Qt::transparent);
        QPainter painter(&mark);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(Qt::NoPen);
        painter.setBrush(QColor(QStringLiteral("#c9a227")));
        painter.drawEllipse(2, 2, 18, 18);
        painter.end();
        tray->setIcon(chotkiIcon.isNull() ? QIcon(mark) : chotkiIcon);
        tray->setToolTip(QStringLiteral("Chotki"));
        auto *menu = new QMenu();
        menu->addAction(QStringLiteral("Open"), window, [window] {
            window->show();
            window->raise();
            window->requestActivate();
        });
        auto *silence = menu->addAction(QStringLiteral("Silence notifications"));
        QObject::connect(&bridge, &Bridge::changed, silence, [&bridge, silence] {
            if (!bridge.settingsReady()) return;
            const bool enabled = bridge.settings().value(QStringLiteral("notifications")).toBool();
            silence->setText(enabled ? QStringLiteral("Silence notifications")
                                     : QStringLiteral("Enable notifications"));
        });
        QObject::connect(silence, &QAction::triggered, &bridge, [&bridge] {
            const bool enabled = bridge.settingsReady()
                && bridge.settings().value(QStringLiteral("notifications")).toBool();
            QVariantMap fields;
            fields.insert(QStringLiteral("notifications"), !enabled);
            bridge.saveSettings(fields);
        });
        QObject::connect(menu, &QMenu::aboutToShow, &bridge, [&bridge] {
            if (!bridge.settingsReady()) bridge.showSettings();
        });
        menu->addAction(QStringLiteral("Settings"), window, [&bridge, window] {
            window->setProperty("section", QStringLiteral("Settings"));
            bridge.showSettings();
            window->show();
            window->raise();
            window->requestActivate();
        });
        auto *quit = menu->addAction(QStringLiteral("Quit"));
        quit->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Q));
        QObject::connect(quit, &QAction::triggered, &application, &QCoreApplication::quit);
        tray->setContextMenu(menu);
        tray->show();
        qInfo("tray available");
    } else if (!screenshot) {
        qInfo("tray unavailable");
    }
    return application.exec();
}
