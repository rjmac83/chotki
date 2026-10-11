#include "ArtworkImage.h"
#include "Bridge.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QWheelEvent>
#include <QtTest>
#include <qqml.h>

#include <algorithm>
#include <memory>

class HomeActionsTest final : public QObject {
    Q_OBJECT

    static QQuickItem *findItem(QQuickItem *root, const QString &name) {
        if (!root) return nullptr;
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems()) {
            if (auto *found = findItem(child, name)) return found;
        }
        return nullptr;
    }

    static QVariant entryValue(const Bridge *bridge, const QString &title, const QString &field) {
        for (const QVariant &item : bridge->entries()) {
            const QVariantMap map = item.toMap();
            if (map.value("title").toString() == title) return map.value(field);
        }
        return {};
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
        const QByteArray review = session->directory.path().toUtf8();
        qputenv("CHOTKI_LINUX_REVIEW_DIR", review);
        qputenv("XDG_DATA_HOME", review);
        session->bridge = std::make_unique<Bridge>(program, true);
        session->engine.rootContext()->setContextProperty("bridge", session->bridge.get());
        session->engine.rootContext()->setContextProperty("playOpening", false);
        session->engine.load(QUrl::fromLocalFile(CHOTKI_QML_SOURCE));
        if (session->engine.rootObjects().size() == 1)
            session->window = qobject_cast<QQuickWindow *>(session->engine.rootObjects().first());
        return session;
    }

    static void revealX(QQuickItem *scroll, QQuickItem *item) {
        if (!scroll || !item) return;
        // A fresh home snapshot replaces the card delegates. Callers must
        // pass the item they just found. Public x() also faults here: the
        // view's position binding word is 1, so the transform is used.
        const double contentX = scroll->property("contentX").toDouble();
        const QPointF viewed = item->mapToItem(scroll, QPointF(0, 0));
        const double limit = std::max(0.0, scroll->property("contentWidth").toDouble() - scroll->width());
        scroll->setProperty("contentX", std::clamp(viewed.x() + contentX - 8.0, 0.0, limit));
    }

    static QPoint sceneCenter(QQuickItem *item) {
        const double width = item->property("width").toDouble();
        const double height = item->property("height").toDouble();
        const QPointF local(width > 1.0 ? width / 2.0 : 16.0, height > 1.0 ? height / 2.0 : 16.0);
        return item->mapToScene(local).toPoint();
    }

    static void click(QQuickWindow *window, QQuickItem *item, Qt::MouseButton button = Qt::LeftButton) {
        QTest::mouseClick(window, button, Qt::NoModifier, sceneCenter(item));
    }

    static void collectHits(QQuickItem *item, const QPointF &scene, QStringList *hits, int depth) {
        if (!item || !item->isVisible() || depth > 12 || hits->size() > 16) return;
        const auto kids = item->childItems();
        for (int i = kids.size() - 1; i >= 0; --i) collectHits(kids.at(i), scene, hits, depth + 1);
        if (!item->contains(item->mapFromScene(scene))) return;
        QString name = item->objectName();
        if (name.isEmpty()) name = QString::fromLatin1(item->metaObject()->className());
        hits->append(name);
    }

    static bool weekSettled(const Bridge *bridge, const QString &date) {
        for (const QVariant &day : bridge->week()) {
            const QVariantMap map = day.toMap();
            if (map.value("date").toString() == date) return map.value("settled").toBool();
        }
        return false;
    }

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void cardsOpenAndTheDayReportsWhatCoreSettled() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program);
        QVERIFY(session && session->window);
        auto *bridge = session->bridge.get();
        auto *window = session->window;
        QTRY_VERIFY_WITH_TIMEOUT(bridge->snapshotReady(), 8000);
        const QString today = bridge->today();
        QVERIFY(!today.isEmpty());

        QQuickItem *strip = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((strip = findItem(window->contentItem(), "card-scroll"))
                                 && strip->property("contentWidth").toDouble() > strip->width() + 20, 3000);
        const QPoint stripCenter = strip->mapToScene(QPointF(strip->width() / 2, 40)).toPoint();
        QWheelEvent wheel(QPointF(stripCenter), window->mapToGlobal(stripCenter), QPoint(), QPoint(0, -120),
                          Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(window, &wheel);
        if (!(strip->property("contentX").toDouble() > 0)) {
            QTest::qWait(50);
            QCoreApplication::sendEvent(strip->window(), &wheel);
        }
        QVERIFY2(strip->property("contentX").toDouble() > 0,
                 qPrintable(QString("contentX %1 contentWidth %2 width %3")
                            .arg(strip->property("contentX").toDouble())
                            .arg(strip->property("contentWidth").toDouble())
                            .arg(strip->width())));

        const QString eveningId = entryValue(bridge, "Evening prayers", "id").toString();
        const QString gospelId = entryValue(bridge, "The day's Gospel", "id").toString();
        QVERIFY(!eveningId.isEmpty() && !gospelId.isEmpty());
        QQuickItem *evening = findItem(window->contentItem(), "card-" + eveningId);
        QQuickItem *gospel = findItem(window->contentItem(), "card-" + gospelId);
        QVERIFY(evening && gospel);
        revealX(strip, evening);
        click(window, evening, Qt::RightButton);
        QQuickItem *kept = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((kept = findItem(window->contentItem(), "card-menu-kept"))
                                 && kept->isVisible(), 3000);
        click(window, kept);
        QTRY_VERIFY_WITH_TIMEOUT(entryValue(bridge, "Evening prayers", "kept").toBool(), 8000);

        strip = findItem(window->contentItem(), "card-scroll");
        gospel = findItem(window->contentItem(), "card-" + gospelId);
        QVERIFY(strip && gospel);
        revealX(strip, gospel);
        click(window, gospel, Qt::RightButton);
        QQuickItem *stand = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((stand = findItem(window->contentItem(), "card-menu-stand"))
                                 && stand->isVisible(), 3000);
        click(window, stand);
        QTRY_VERIFY_WITH_TIMEOUT(entryValue(bridge, "The day's Gospel", "stoodDown").toBool()
                                 && !entryValue(bridge, "The day's Gospel", "kept").toBool(), 8000);

        const bool reported = weekSettled(bridge, bridge->selectedDate());
        QQuickItem *dot = findItem(window->contentItem(), "settled-" + bridge->selectedDate());
        QVERIFY(dot);
        QCOMPARE(dot->isVisible(), reported);
        QVERIFY(!reported);

        evening = findItem(window->contentItem(), "card-" + eveningId);
        QVERIFY(evening);
        revealX(strip, evening);
        click(window, evening);
        QTRY_COMPARE(window->property("section").toString(), QString("Prayers"));
        QTRY_COMPARE_WITH_TIMEOUT(bridge->prayerSelection(), QString("evening"), 8000);
        QTRY_COMPARE_WITH_TIMEOUT(bridge->showsRope(), false, 8000);

        QTest::keyClick(window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QString("Home"));
        dot = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((dot = findItem(window->contentItem(), "settled-" + today))
                                 && dot->isVisible() == weekSettled(bridge, today), 3000);
        QVERIFY(!weekSettled(bridge, today));

        strip = findItem(window->contentItem(), "card-scroll");
        QVERIFY(strip);
        const QString jesusId = entryValue(bridge, "The Jesus Prayer", "id").toString();
        QVERIFY(!jesusId.isEmpty());
        QQuickItem *jesus = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((jesus = findItem(window->contentItem(), "card-" + jesusId)), 3000);
        revealX(strip, jesus);
        click(window, jesus);
        QTRY_COMPARE(window->property("section").toString(), QString("Prayers"));
        QTRY_COMPARE_WITH_TIMEOUT(bridge->prayerSelection(), QString("jesus-prayer"), 8000);
        QTRY_COMPARE_WITH_TIMEOUT(bridge->showsRope(), true, 8000);

        QTest::keyClick(window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QString("Home"));
        QTRY_VERIFY_WITH_TIMEOUT((strip = findItem(window->contentItem(), "card-scroll"))
                                 && (gospel = findItem(window->contentItem(), "card-" + gospelId)), 3000);
        revealX(strip, gospel);
        click(window, gospel);
        QTRY_COMPARE(window->property("section").toString(), QString("Reading"));
        QTRY_VERIFY_WITH_TIMEOUT(bridge->readingReady(), 8000);
        bool gospelOpen = false;
        for (const QVariant &section : bridge->readingSections()) {
            const QVariantMap map = section.toMap();
            if (map.value("band").toInt() == 0 && map.value("open").toBool()) gospelOpen = true;
        }
        QVERIFY(gospelOpen);

        QTest::keyClick(window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QString("Home"));
        QString other;
        for (const QVariant &day : bridge->week()) {
            const QString date = day.toMap().value("date").toString();
            if (!date.isEmpty() && date != today) {
                other = date;
                break;
            }
        }
        QVERIFY(!other.isEmpty());
        QQuickItem *week = nullptr;
        QQuickItem *otherDay = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((week = findItem(window->contentItem(), "week-scroll"))
                                 && (otherDay = findItem(window->contentItem(), "day-" + other))
                                 && otherDay->width() > 20 && otherDay->height() > 20, 3000);
        const QPointF localCenter(otherDay->width() / 2.0, otherDay->height() / 2.0);
        const QPointF inWeek = otherDay->mapToItem(week, localCenter);
        const QPoint center = otherDay->mapToScene(localCenter).toPoint();
        const QString where = QString("scene %1,%2 inWeek %3,%4 size %5x%6")
                                  .arg(center.x()).arg(center.y())
                                  .arg(inWeek.x()).arg(inWeek.y())
                                  .arg(otherDay->width()).arg(otherDay->height());
        QVERIFY2(inWeek.x() >= 0 && inWeek.x() < week->width()
                 && inWeek.y() >= 0 && inWeek.y() < week->height(),
                 qPrintable(where));
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center);
        QVERIFY2(QTest::qWaitFor([&] { return bridge->selectedDate() == other; }, 8000),
                 qPrintable([&] {
                     QStringList hits;
                     collectHits(window->contentItem(), center, &hits, 0);
                     return QString("selected %1 wanted %2 %3 picked %4 error %5 hits %6")
                         .arg(bridge->selectedDate(), other, where, week->property("picked").toString(),
                              bridge->error(), hits.join(QStringLiteral(" > ")));
                 }()));
        QQuickItem *link = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((link = findItem(window->contentItem(), "today-link"))
                                 && link->isVisible(), 3000);
        const QString backward = QString(QChar(0x2190)) + QStringLiteral(" Today");
        const QString forward = QStringLiteral("Today ") + QString(QChar(0x2192));
        QCOMPARE(bridge->todayLink(), other > today ? backward : forward);
        QCOMPARE(link->property("text").toString(), bridge->todayLink());
        click(window, link);
        QTRY_COMPARE_WITH_TIMEOUT(bridge->selectedDate(), today, 8000);
        QTRY_VERIFY_WITH_TIMEOUT((link = findItem(window->contentItem(), "today-link"))
                                 && !link->isVisible(), 3000);

        bridge->selectDate(QStringLiteral("2026-10-07"));
        QTRY_COMPARE_WITH_TIMEOUT(bridge->selectedDate(), QString("2026-10-07"), 8000);
        const QString fastId = entryValue(bridge, "The Wednesday and Friday fast", "id").toString();
        QVERIFY(!fastId.isEmpty());
        QQuickItem *fast = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((strip = findItem(window->contentItem(), "card-scroll"))
                                 && (fast = findItem(window->contentItem(), "card-" + fastId)), 3000);
        revealX(strip, fast);
        click(window, fast);
        QCOMPARE(window->property("section").toString(), QString("Home"));
        QVERIFY(fast->property("flipped").toBool());
        QQuickItem *summary = findItem(window->contentItem(), "card-summary-" + fastId);
        QVERIFY(summary);
        QCOMPARE(summary->property("text").toString(),
                 entryValue(bridge, "The Wednesday and Friday fast", "back").toString());
        QVERIFY(summary->property("text").toString().contains(QStringLiteral("ordinary weekly fast")));

        const QString morningId = entryValue(bridge, "Morning prayers", "id").toString();
        QQuickItem *morning = findItem(window->contentItem(), "card-" + morningId);
        QVERIFY(morning);
        revealX(strip, morning);
        click(window, morning, Qt::RightButton);
        QQuickItem *edit = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((edit = findItem(window->contentItem(), "card-menu-edit"))
                                 && edit->isVisible(), 3000);
        click(window, edit);
        QTRY_COMPARE(window->property("section").toString(), QString("Library"));
        QQuickItem *title = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((title = findItem(window->contentItem(), "editor-title"))
                                 && title->property("text").toString() == QString("Morning prayers"),
                                 8000);

        QTest::keyClick(window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QString("Home"));
        bridge->selectDate(QStringLiteral("2027-05-05"));
        QTRY_COMPARE_WITH_TIMEOUT(bridge->selectedDate(), QString("2027-05-05"), 8000);
        const QString liftedId = entryValue(bridge, "The Wednesday and Friday fast", "id").toString();
        QVERIFY(entryValue(bridge, "The Wednesday and Friday fast", "dispensed").toBool());
        QTRY_VERIFY_WITH_TIMEOUT((strip = findItem(window->contentItem(), "card-scroll"))
                                 && (fast = findItem(window->contentItem(), "card-" + liftedId)), 3000);
        revealX(strip, fast);
        click(window, fast, Qt::RightButton);
        QQuickItem *lifted = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((lifted = findItem(window->contentItem(), "card-menu-lifted"))
                                 && lifted->isVisible(), 3000);
        QQuickItem *keptOnFast = findItem(window->contentItem(), "card-menu-kept");
        QVERIFY(keptOnFast && !keptOnFast->isVisible());
        QQuickItem *lateOnFast = findItem(window->contentItem(), "card-menu-late");
        QVERIFY(lateOnFast && !lateOnFast->isVisible());
        QCOMPARE(window->property("section").toString(), QString("Home"));
    }

    void monthBesideTheDayAndTheSayingRests() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");
        const auto session = openSession(program);
        QVERIFY(session && session->window);
        auto *bridge = session->bridge.get();
        auto *window = session->window;
        QTRY_VERIFY_WITH_TIMEOUT(bridge->snapshotReady() && bridge->month().size() == 42, 8000);

        int inside = 0;
        QString prefix;
        for (const QVariant &cell : bridge->month()) {
            const QVariantMap day = cell.toMap();
            if (day.value(QStringLiteral("weekday")).toInt() == 1)
                QVERIFY(!day.value(QStringLiteral("fast")).toBool());
            if (!day.value(QStringLiteral("inMonth")).toBool()) continue;
            ++inside;
            const QString date = day.value(QStringLiteral("date")).toString();
            if (prefix.isEmpty()) prefix = date.left(7);
            QCOMPARE(date.left(7), prefix);
        }
        QVERIFY(inside >= 28 && inside <= 31);
        const QString title = bridge->monthTitle();
        QVERIFY(title.endsWith(prefix.left(4)));

        QQuickItem *grid = nullptr;
        QQuickItem *week = nullptr;
        QQuickItem *art = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((grid = findItem(window->contentItem(), "month-grid"))
                                 && grid->isVisible() && grid->height() > 100
                                 && (week = findItem(window->contentItem(), "week-scroll"))
                                 && week->isVisible()
                                 && (art = findItem(window->contentItem(), "saying-art"))
                                 && art->property("progress").toDouble() == 1.0, 3000);
        QVERIFY(findItem(window->contentItem(), "edge-fade"));

        QString titled;
        for (const QVariant &item : bridge->entries()) {
            const QString id = item.toMap().value(QStringLiteral("id")).toString();
            QQuickItem *label = findItem(window->contentItem(), "card-title-" + id);
            if (!label) continue;
            titled = id;
            QCOMPARE(label->property("fontSizeMode").toInt(), 3);
            QCOMPARE(label->property("minimumPixelSize").toInt(), 11);
            QCOMPARE(label->property("height").toDouble(), 56.0);
            break;
        }
        QVERIFY(!titled.isEmpty());

        const QString selected = bridge->selectedDate();
        QQuickItem *next = findItem(window->contentItem(), "month-next");
        QVERIFY(next && next->isVisible());
        click(window, next);
        QTRY_VERIFY_WITH_TIMEOUT(bridge->monthTitle() != title && bridge->month().size() == 42, 8000);
        QCOMPARE(bridge->selectedDate(), selected);
        int after = 0;
        QString moved;
        for (const QVariant &cell : bridge->month()) {
            const QVariantMap day = cell.toMap();
            if (!day.value(QStringLiteral("inMonth")).toBool()) continue;
            ++after;
            if (moved.isEmpty()) moved = day.value(QStringLiteral("date")).toString().left(7);
        }
        QVERIFY(after >= 28 && after <= 31);
        QVERIFY(moved != prefix);
    }
};

QTEST_MAIN(HomeActionsTest)
#include "HomeActionsTest.moc"
