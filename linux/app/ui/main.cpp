#include "Bridge.h"
#include "ArtworkImage.h"
#include "Opening.h"

#include <QGuiApplication>
#include <QDir>
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
    QGuiApplication application(argc, argv);
    application.setApplicationName("Chotki");
    application.setDesktopFileName("org.chotki.Chotki");

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
    return application.exec();
}
