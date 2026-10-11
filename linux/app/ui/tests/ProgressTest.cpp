#include "Bridge.h"
#include "ArtworkImage.h"

#include <QColor>
#include <QDate>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>
#include <qqml.h>

#include <memory>

class ProgressTest final : public QObject {
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

    static bool showsExactText(QQuickItem *root, const QString &wanted) {
        if (!root || !root->isVisible()) return false;
        if (root->property("text").toString() == wanted) return true;
        for (QQuickItem *child : root->childItems()) {
            if (showsExactText(child, wanted)) return true;
        }
        return false;
    }

    static QString longDate(const QDate &date) {
        static const char *weekdays[] = {
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"};
        static const char *months[] = {
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"};
        return QString("%1 %2 %3")
            .arg(QString::fromLatin1(weekdays[date.dayOfWeek() - 1]))
            .arg(date.day())
            .arg(QString::fromLatin1(months[date.month() - 1]));
    }

    static void collectText(QQuickItem *root, QStringList *lines, bool *red) {
        if (!root || !root->isVisible()) return;
        const QString text = root->property("text").toString();
        if (!text.isEmpty()) {
            lines->push_back(text);
            const QColor color = root->property("color").value<QColor>();
            if (color.isValid() && color.red() > color.green() + 40 && color.red() > color.blue() + 40)
                *red = true;
        }
        for (QQuickItem *child : root->childItems()) collectText(child, lines, red);
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

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void keptAndMissedDayIsNotAFailure() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        QString artwork = qEnvironmentVariable("CHOTKI_ARTWORK_ROOT");
        if (artwork.isEmpty()) artwork = QStringLiteral(CHOTKI_ARTWORK_SOURCE);
        QVERIFY2(QFileInfo::exists(QDir(artwork).filePath("progress.jpg")), qPrintable(artwork));
        qputenv("CHOTKI_ARTWORK_ROOT", artwork.toUtf8());

        const auto session = openSession(program);
        QVERIFY(session && session->window);
        QVERIFY(!session->bridge->progressArtworkUrl().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->snapshotReady(), 8000);
        QVERIFY(session->bridge->entries().isEmpty());

        const QDate today = QDate::fromString(session->bridge->today(), Qt::ISODate);
        QVERIFY(today.isValid());
        const QDate keptDay = today.addDays(-3);
        const QDate stoodDay = today.addDays(-1);
        const QString kept = keptDay.toString(Qt::ISODate);
        const QString stood = stoodDay.toString(Qt::ISODate);

        session->bridge->prepareTemplate("morning-prayers");
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->editorPage().value("open").toBool(), 8000);
        session->bridge->saveRule({{"from", kept}});
        QTRY_COMPARE_WITH_TIMEOUT(entryValue(session->bridge.get(), "Morning prayers", "time").toString(),
                                  QString("06:30"), 8000);
        const QString ruleID = entryValue(session->bridge.get(), "Morning prayers", "id").toString();
        QVERIFY(!ruleID.isEmpty());

        session->bridge->selectDate(kept);
        QTRY_VERIFY_WITH_TIMEOUT(entryValue(session->bridge.get(), "Morning prayers", "id").toString() == ruleID
                                 && session->bridge->selectedDate() == kept, 8000);
        session->bridge->toggleKept(ruleID);
        QTRY_VERIFY_WITH_TIMEOUT(entryValue(session->bridge.get(), "Morning prayers", "kept").toBool(), 8000);

        session->bridge->selectDate(stood);
        QTRY_COMPARE_WITH_TIMEOUT(session->bridge->selectedDate(), stood, 8000);
        session->bridge->standDownDay(ruleID);
        QTRY_VERIFY_WITH_TIMEOUT(entryValue(session->bridge.get(), "Morning prayers", "stoodDown").toBool(), 8000);

        QQuickItem *nav = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((nav = findItem(session->window->contentItem(), "nav-Progress"))
                                 && nav->isVisible() && nav->width() > 0, 3000);
        const QPoint center = nav->mapToScene(QPointF(nav->width() / 2, nav->height() / 2)).toPoint();
        QTest::mouseClick(session->window, Qt::LeftButton, Qt::NoModifier, center);
        QTRY_COMPARE(session->window->property("section").toString(), QString("Progress"));

        QQuickItem *page = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((page = findItem(session->window->contentItem(), "progress"))
                                 && page->isVisible(), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(session->bridge->progressReady(), 8000);

        const QString heading = QString("Your progress up to %1").arg(longDate(stoodDay));
        QCOMPARE(session->bridge->progressThrough(), stood);
        QCOMPARE(session->bridge->progressHeading(), heading);
        QVERIFY(heading != QString("Your progress up to %1").arg(longDate(today)));
        QTRY_VERIFY_WITH_TIMEOUT(showsExactText(page, heading), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(showsExactText(page, "Morning prayers slipped once."), 8000);
        QVERIFY(showsExactText(page, "One day was stood down and is not counted either way."));
        QVERIFY(showsExactText(page, "1 of 2"));
        QVERIFY(showsExactText(page, "50%"));
        QVERIFY(showsExactText(page, "Kept, over the 30 days to then"));

        QQuickItem *count = findItem(page, "progress-count");
        QVERIFY(count && count->isVisible());
        QCOMPARE(count->property("text").toString(), QString("1 of 2"));
        const QColor countColor = count->property("color").value<QColor>();
        QCOMPARE(countColor, QColor(0xa3, 0x9e, 0x8f));

        QStringList texts;
        bool red = false;
        collectText(page, &texts, &red);
        QVERIFY(!red);
        for (const QString &text : texts) {
            QVERIFY2(!text.contains("failed", Qt::CaseInsensitive), qPrintable(text));
            QVERIFY2(!text.contains("in a row", Qt::CaseInsensitive), qPrintable(text));
        }

        QQuickItem *art = findItem(page, "progress-art");
        QQuickItem *quote = findItem(page, "progress-quote");
        QQuickItem *caption = findItem(page, "progress-caption");
        QVERIFY(art && quote && quote->isVisible() && caption && caption->isVisible());
        const QPointF quoteAt = quote->mapToItem(art, QPointF(0, 0));
        QVERIFY(quoteAt.y() >= 0);
        QVERIFY(quoteAt.y() < art->height());
        QVERIFY(quote->property("text").toString().contains(
            "Those who have really determined to serve Christ"));
        QCOMPARE(caption->property("text").toString(),
                 QString("Icon of St. Anthony the Great, St. Paul of Thebes, "
                         "St. Sabbas the Sanctified, and St. John Climacus."));
        QQuickItem *image = findItem(page, "progress-image");
        QVERIFY(image);
        QCOMPARE(image->property("source").toUrl(), QUrl(session->bridge->progressArtworkUrl()));
    }
};

QTEST_MAIN(ProgressTest)
#include "ProgressTest.moc"
