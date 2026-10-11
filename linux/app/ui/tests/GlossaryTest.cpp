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
#include <memory>

class GlossaryTest final : public QObject {
    Q_OBJECT

    static QQuickItem *findItem(QQuickItem *root, const QString &name) {
        if (!root) return nullptr;
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems()) {
            if (auto *found = findItem(child, name)) return found;
        }
        return nullptr;
    }

    static void collect(QQuickItem *root, const QString &name, QList<QQuickItem *> *out) {
        if (!root) return;
        if (root->objectName() == name) out->append(root);
        for (QQuickItem *child : root->childItems()) collect(child, name, out);
    }

    static bool showsText(QQuickItem *root, const QString &fragment) {
        QList<QQuickItem *> lines;
        collect(root, QStringLiteral("prayer-line"), &lines);
        for (QQuickItem *line : lines) {
            if (line->property("plain").toString().contains(fragment)) return true;
        }
        return false;
    }

    static bool containsText(QQuickItem *root, const QString &word) {
        if (!root) return false;
        if (root->property("text").toString().contains(word, Qt::CaseInsensitive)) return true;
        for (QQuickItem *child : root->childItems()) {
            if (containsText(child, word)) return true;
        }
        return false;
    }

    // linkAt is how a click finds the term. Re-find the line each time; the
    // prayer column is rebuilt when the selection changes.
    static QPoint linkPoint(QQuickItem *root, const QString &slug) {
        QList<QQuickItem *> lines;
        collect(root, QStringLiteral("prayer-line"), &lines);
        for (QQuickItem *line : lines) {
            if (!line->isVisible()) continue;
            const qreal width = line->width();
            const qreal height = line->height();
            if (width < 8 || height < 8) continue;
            for (qreal y = 3; y < height; y += 5) {
                for (qreal x = 3; x < width; x += 6) {
                    QString link;
                    const bool called = QMetaObject::invokeMethod(
                        line, "linkAt", Qt::DirectConnection, Q_RETURN_ARG(QString, link),
                        Q_ARG(qreal, x), Q_ARG(qreal, y));
                    if (called && link == slug)
                        return line->mapToScene(QPointF(x, y)).toPoint();
                }
            }
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

    static QVariant entryValue(const Bridge *bridge, const QString &title, const QString &field) {
        for (const QVariant &item : bridge->entries()) {
            const QVariantMap map = item.toMap();
            if (map.value("title").toString() == title) return map.value(field);
        }
        return {};
    }

    static void revealX(QQuickItem *scroll, QQuickItem *item) {
        if (!scroll || !item) return;
        const double contentX = scroll->property("contentX").toDouble();
        const QPointF viewed = item->mapToItem(scroll, QPointF(0, 0));
        const double limit = std::max(0.0, scroll->property("contentWidth").toDouble() - scroll->width());
        scroll->setProperty("contentX", std::clamp(viewed.x() + contentX - 8.0, 0.0, limit));
    }

    static QString glossaryState(QQuickWindow *window, Bridge *bridge) {
        QQuickItem *term = findItem(window->contentItem(), QStringLiteral("glossary-term"));
        const QString shown = term ? term->property("text").toString() : QStringLiteral("<missing>");
        const QString held = bridge->glossaryEntry().value(QStringLiteral("term")).toString();
        return shown + QLatin1Char('|') + held + QLatin1Char('|')
            + window->property("section").toString();
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

    static void click(QQuickWindow *window, QQuickItem *item, Qt::MouseButton button = Qt::LeftButton) {
        const double width = std::max(item->width(), item->property("implicitWidth").toDouble());
        const double height = std::max(item->height(), item->property("implicitHeight").toDouble());
        const QPointF local(width > 1.0 ? width / 2.0 : 8.0, height > 1.0 ? height / 2.0 : 8.0);
        QTest::mouseClick(window, button, Qt::NoModifier, item->mapToScene(local).toPoint());
    }

private slots:
    void initTestCase() {
        qmlRegisterType<ArtworkImage>("ChotkiArtwork", 1, 0, "ArtworkImage");
    }

    void followAmenFromAPrayerAndBack() {
        const QString program = qEnvironmentVariable("CHOTKI_LINUX_BRIDGE");
        if (program.isEmpty()) QSKIP("CHOTKI_LINUX_BRIDGE is not set");

        const auto session = openSession(program);
        QVERIFY(session && session->window);
        auto *bridge = session->bridge.get();
        auto *window = session->window;
        QTRY_VERIFY_WITH_TIMEOUT(bridge->snapshotReady(), 8000);

        QTest::keyClick(window, Qt::Key_2, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QString("Prayers"));
        QTRY_VERIFY_WITH_TIMEOUT(showsText(window->contentItem(),
            QStringLiteral("Lord Jesus Christ, Son of God, have mercy on me, a sinner.")), 8000);

        bridge->choosePrayer(QStringLiteral("beginning"));
        QTRY_COMPARE_WITH_TIMEOUT(bridge->prayerSelection(), QString("beginning"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(showsText(window->contentItem(),
                                            QStringLiteral("In the name of the Father")), 8000);

        QPoint amen;
        QTRY_VERIFY_WITH_TIMEOUT((amen = linkPoint(window->contentItem(), QStringLiteral("amen")), !amen.isNull()),
                                 8000);
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, amen);
        QTRY_COMPARE_WITH_TIMEOUT(window->property("section").toString(), QString("Glossary"), 8000);

        QQuickItem *term = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((term = findItem(window->contentItem(), "glossary-term"))
                                 && term->isVisible()
                                 && term->property("text").toString() == QString("Amen"), 8000);
        QQuickItem *note = findItem(window->contentItem(), "glossary-note");
        QVERIFY(note && note->isVisible());
        const QString caveat = note->property("text").toString();
        QVERIFY(caveat.contains(QStringLiteral("Introductory")));
        QVERIFY(caveat.contains(QStringLiteral("not a ruling")));
        QCOMPARE(caveat, bridge->glossaryNote());
        QQuickItem *said = findItem(window->contentItem(), "glossary-pronunciation");
        QVERIFY(said && said->property("text").toString() == QString("AH-meen"));
        QQuickItem *body = findItem(window->contentItem(), "glossary-body");
        QVERIFY(body && body->property("text").toString().contains(QStringLiteral("Amen is not punctuation")));
        QQuickItem *glossary = findItem(window->contentItem(), "glossary");
        QVERIFY(glossary && !containsText(glossary, QStringLiteral("failed")));

        QQuickItem *related = nullptr;
        QQuickItem *scroll = findItem(window->contentItem(), "glossary-scroll");
        QVERIFY(scroll);
        QTRY_VERIFY_WITH_TIMEOUT((related = findItem(window->contentItem(), "glossary-related-prayer-rule"))
                                 && related->width() > 2.0 && related->height() > 2.0, 3000);
        for (int attempt = 0; attempt < 4; ++attempt) {
            if (bridge->glossaryEntry().value(QStringLiteral("term")).toString() == QStringLiteral("Prayer rule"))
                break;
            scroll = findItem(window->contentItem(), QStringLiteral("glossary-scroll"));
            related = findItem(window->contentItem(), QStringLiteral("glossary-related-prayer-rule"));
            if (!scroll || !related) {
                QTest::qWait(50);
                continue;
            }
            if (!centerInView(scroll, related)) revealY(scroll, related);
            related = findItem(window->contentItem(), QStringLiteral("glossary-related-prayer-rule"));
            scroll = findItem(window->contentItem(), QStringLiteral("glossary-scroll"));
            if (related && scroll && centerInView(scroll, related)) click(window, related);
            QTest::qWait(200);
        }
        QTRY_COMPARE_WITH_TIMEOUT(glossaryState(window, bridge),
                                  QStringLiteral("Prayer rule|Prayer rule|Glossary"), 8000);

        QQuickItem *back = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((back = findItem(window->contentItem(), "glossary-back"))
                                 && back->isVisible(), 3000);
        click(window, back);
        QTRY_COMPARE_WITH_TIMEOUT(window->property("section").toString(), QString("Prayers"), 8000);
        QTRY_COMPARE_WITH_TIMEOUT(bridge->prayerSelection(), QString("beginning"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(showsText(window->contentItem(),
                                            QStringLiteral("In the name of the Father")), 8000);

        QTest::keyClick(window, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(window->property("section").toString(), QString("Home"));
        const QString morningId = entryValue(bridge, QStringLiteral("Morning prayers"), QStringLiteral("id")).toString();
        QCOMPARE(entryValue(bridge, QStringLiteral("Morning prayers"), QStringLiteral("glossarySlug")).toString(),
                 QString("prayer-rule"));
        QQuickItem *strip = nullptr;
        QQuickItem *morning = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((strip = findItem(window->contentItem(), "card-scroll"))
                                 && (morning = findItem(window->contentItem(), "card-" + morningId)), 3000);
        revealX(strip, morning);
        click(window, morning, Qt::RightButton);
        QQuickItem *about = nullptr;
        QTRY_VERIFY_WITH_TIMEOUT((about = findItem(window->contentItem(), "card-menu-about"))
                                 && about->isVisible(), 3000);
        click(window, about);
        QTRY_COMPARE_WITH_TIMEOUT(window->property("section").toString(), QString("Glossary"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT((term = findItem(window->contentItem(), "glossary-term"))
                                 && term->property("text").toString() == QString("Prayer rule"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT((back = findItem(window->contentItem(), "glossary-back"))
                                 && back->isVisible(), 3000);
        click(window, back);
        QTRY_COMPARE_WITH_TIMEOUT(window->property("section").toString(), QString("Home"), 8000);
    }
};

QTEST_MAIN(GlossaryTest)
#include "GlossaryTest.moc"
