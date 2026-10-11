#include "Bridge.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QProcess>
#include <QDate>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <utility>

Bridge::Bridge(QString program, bool review, QObject *parent)
    : QObject(parent), m_program(std::move(program)), m_review(review) {
    m_artworkRoot = qEnvironmentVariable("CHOTKI_ARTWORK_ROOT");
    QFile orderFile(QDir(m_artworkRoot).filePath("sayings/order.txt"));
    if (!m_artworkRoot.isEmpty() && orderFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        for (const QByteArray &line : orderFile.readAll().split('\n')) {
            const QString name = QString::fromUtf8(line).trimmed();
            if (!name.isEmpty()) m_artworkOrder.push_back(name);
        }
    }
    const QString progressImage = QDir(m_artworkRoot).filePath("progress.jpg");
    if (!m_artworkRoot.isEmpty() && QFileInfo::exists(progressImage))
        m_progressArtworkUrl = QUrl::fromLocalFile(progressImage).toString();
    connect(&m_process, &QProcess::started, this, [this] {
        m_status = "Loading your record…";
        m_error.clear();
        emit changed();
        send("hello");
        refresh();
        refreshPrayer();
        send("opening");
        send("tones");
    });
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &Bridge::readResponses);
    connect(&m_process, &QProcess::finished, this, &Bridge::stopped);
    connect(&m_process, &QProcess::errorOccurred, this, [this] {
        m_error = m_process.errorString();
        m_connected = false;
        emit changed();
    });
    start();
}

Bridge::~Bridge() {
    m_closing = true;
    m_process.closeWriteChannel();
    if (m_process.state() != QProcess::NotRunning && !m_process.waitForFinished(1500)) {
        m_process.kill();
        m_process.waitForFinished(1500);
    }
}

void Bridge::start() {
    m_pending.clear();
    m_snapshotReady = false;
    m_process.start(m_program, {m_review ? "--review" : "--normal"});
}

void Bridge::stopped() {
    m_connected = false;
    m_snapshotReady = false;
    if (m_closing) return;
    if (m_restarts >= 3) {
        m_status = "The record could not be opened";
        m_error = "The Swift helper stopped repeatedly. Restart Chotki after checking its installation.";
        emit changed();
        return;
    }
    ++m_restarts;
    m_status = "Reconnecting to the record…";
    emit changed();
    QTimer::singleShot(500 * m_restarts, this, [this] { if (!m_closing) start(); });
}

namespace {

struct BridgeResponse {
    int version = 0;
    int id = 0;
    bool ok = false;
    QString error;
    bool hasMode = false;
    bool hasDisplayName = false;
    QString displayName;
    bool hasToday = false;
    QString today;
    bool hasSelectedDate = false;
    QString selectedDate;
    bool hasDayTitle = false;
    QString dayTitle;
    bool hasObservedDate = false;
    QString observedDate;
    bool hasShowOldStyleDates = false;
    bool showOldStyleDates = false;
    bool hasSayingText = false;
    QString sayingText;
    bool hasSayingAuthor = false;
    QString sayingAuthor;
    bool hasSayingSource = false;
    QString sayingSource;
    bool hasEntries = false;
    QVariantList entries;
    bool hasWeek = false;
    QVariantList week;
    bool hasPsalmOneVerses = false;
    int psalmOneVerses = 0;
    bool hasPrayer = false;
    QJsonObject prayer;
    bool hasOpening = false;
    QJsonObject opening;
    bool hasTones = false;
    QJsonObject tones;
    bool hasReading = false;
    QJsonObject reading;
    bool hasPsalter = false;
    QJsonObject psalter;
    bool hasLibrary = false;
    QJsonObject library;
    bool hasEditor = false;
    QJsonObject editor;
    bool hasProgress = false;
    QJsonObject progress;
    bool hasGlossary = false;
    QJsonObject glossary;
    bool hasSettings = false;
    QJsonObject settings;
    bool hasNeedsWelcome = false;
    bool needsWelcome = false;
    bool hasReducedMotion = false;
    bool reducedMotion = false;
    bool hasTodayLink = false;
    QString todayLink;
    bool hasThanksgiving = false;
    QString thanksgiving;
    bool home = false;
};

BridgeResponse decodeResponse(const QJsonObject &object) {
    BridgeResponse response;
    response.version = object.value("v").toInt();
    response.id = object.value("id").toInt();
    response.ok = object.value("ok").toBool();
    response.error = object.value("error").toString();
    response.hasMode = object.contains("mode");
    response.hasDisplayName = object.contains("displayName");
    response.displayName = object.value("displayName").toString();
    response.hasToday = object.contains("today");
    response.today = object.value("today").toString();
    response.hasSelectedDate = object.contains("selectedDate");
    response.selectedDate = object.value("selectedDate").toString();
    response.hasDayTitle = object.contains("dayTitle");
    response.dayTitle = object.value("dayTitle").toString();
    response.hasObservedDate = object.contains("observedDate");
    response.observedDate = object.value("observedDate").toString();
    response.hasShowOldStyleDates = object.contains("showOldStyleDates");
    response.showOldStyleDates = object.value("showOldStyleDates").toBool();
    response.hasSayingText = object.contains("sayingText");
    response.sayingText = object.value("sayingText").toString();
    response.hasSayingAuthor = object.contains("sayingAuthor");
    response.sayingAuthor = object.value("sayingAuthor").toString();
    response.hasSayingSource = object.contains("sayingSource");
    response.sayingSource = object.value("sayingSource").toString();
    response.hasEntries = object.contains("entries");
    response.entries = object.value("entries").toArray().toVariantList();
    response.hasWeek = object.contains("week");
    response.week = object.value("week").toArray().toVariantList();
    response.hasPsalmOneVerses = object.contains("psalmOneVerses");
    response.psalmOneVerses = object.value("psalmOneVerses").toInt();
    response.hasPrayer = object.contains("prayer");
    response.prayer = object.value("prayer").toObject();
    response.hasOpening = object.contains("opening");
    response.opening = object.value("opening").toObject();
    response.hasTones = object.contains("tones");
    response.tones = object.value("tones").toObject();
    response.hasReading = object.contains("reading");
    response.reading = object.value("reading").toObject();
    response.hasPsalter = object.contains("psalter");
    response.psalter = object.value("psalter").toObject();
    response.hasLibrary = object.contains("library");
    response.library = object.value("library").toObject();
    response.hasEditor = object.contains("editor");
    response.editor = object.value("editor").toObject();
    response.hasProgress = object.contains("progress");
    response.progress = object.value("progress").toObject();
    response.hasGlossary = object.contains("glossary");
    response.glossary = object.value("glossary").toObject();
    response.hasSettings = object.contains("settings");
    response.settings = object.value("settings").toObject();
    response.hasNeedsWelcome = object.contains("needsWelcome");
    response.needsWelcome = object.value("needsWelcome").toBool();
    response.hasReducedMotion = object.contains("reducedMotion");
    response.reducedMotion = object.value("reducedMotion").toBool();
    response.hasTodayLink = object.contains("todayLink");
    response.todayLink = object.value("todayLink").toString();
    response.hasThanksgiving = object.contains("thanksgiving");
    response.thanksgiving = object.value("thanksgiving").toString();
    // todayLink and thanksgiving are not home by themselves. A prayer reply
    // must not be treated as a day snapshot, and a missing thanksgiving must
    // not count as a new one.
    response.home = response.hasDisplayName || response.hasToday || response.hasSelectedDate
        || response.hasDayTitle || response.hasObservedDate || response.hasShowOldStyleDates
        || response.hasSayingText || response.hasSayingAuthor || response.hasSayingSource
        || response.hasEntries || response.hasWeek || response.hasPsalmOneVerses;
    return response;
}

}

void Bridge::send(const QString &operation, const QJsonObject &fields) {
    if (m_process.state() != QProcess::Running) return;
    QJsonObject request{{"v", protocolVersion}, {"id", m_nextId++}, {"op", operation}};
    for (auto it = fields.begin(); it != fields.end(); ++it) request.insert(it.key(), it.value());
    m_process.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
}

void Bridge::refresh() { send("snapshot"); }
void Bridge::setReviewName(const QString &name) { if (m_review) send("setReviewName", QJsonObject{{"name", name}}); }
void Bridge::selectDate(const QString &date) { send("selectDate", QJsonObject{{"date", date}}); }
void Bridge::toggleKept(const QString &ruleID) { send("toggleKept", QJsonObject{{"ruleID", ruleID}}); }

void Bridge::markKeptLate(const QString &ruleID) {
    send("markKeptLate", QJsonObject{{"ruleID", ruleID}});
}

void Bridge::standDownDay(const QString &ruleID) {
    send("standDownDay", QJsonObject{{"ruleID", ruleID}});
}
void Bridge::shiftWeek(int direction) {
    if (direction == -1 || direction == 1) send("shiftWeek", QJsonObject{{"direction", direction}});
}

void Bridge::refreshPrayer() { send("prayer", QJsonObject{{"diameter", m_ropeDiameter}}); }

void Bridge::choosePrayer(const QString &selection) {
    send("choosePrayer", QJsonObject{{"selection", selection.isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(selection)}});
}

void Bridge::advancePrayer() { send("advancePrayer"); }

void Bridge::advancePrayerAt(double now) { send("advancePrayer", QJsonObject{{"now", now}}); }

void Bridge::aimPrayer(int target) { send("aimPrayer", QJsonObject{{"target", target}}); }

void Bridge::showRope(bool shown) { send("showRope", QJsonObject{{"shown", shown}}); }

void Bridge::startAgain() { send("startAgain"); }

void Bridge::showReading() { send("openReading", QJsonObject{{"band", QJsonValue(QJsonValue::Null)}}); }

void Bridge::openReading(int band) {
    if (band < 0) showReading();
    else send("openReading", QJsonObject{{"band", band}});
}

void Bridge::toggleReading(int band) { send("toggleReading", QJsonObject{{"band", band}}); }

void Bridge::finishReading(int band) { send("finishReading", QJsonObject{{"band", band}}); }

void Bridge::refreshPsalter() { send("psalter"); }

void Bridge::openKathisma(int number, bool manual) {
    send("openKathisma", QJsonObject{{"kathisma", number}, {"manual", manual}});
}

void Bridge::finishPsalter() { send("finishPsalter"); }

void Bridge::showLibrary(const QString &query) { send("library", QJsonObject{{"query", query}}); }

void Bridge::showProgress() { send("progress"); }

void Bridge::showGlossary(const QString &slug, const QString &query) {
    QJsonObject fields;
    if (!slug.isEmpty()) fields.insert(QStringLiteral("slug"), slug);
    if (!query.isEmpty()) fields.insert(QStringLiteral("query"), query);
    send(QStringLiteral("glossary"), fields);
}

void Bridge::showSettings() { send(QStringLiteral("settings")); }

void Bridge::saveSettings(const QVariantMap &fields) {
    send(QStringLiteral("saveSettings"), QJsonObject::fromVariantMap(fields));
}

void Bridge::exportBackup(const QString &path) {
    send(QStringLiteral("exportBackup"), QJsonObject{{QStringLiteral("path"), path}});
}

void Bridge::importBackup(const QString &path) {
    send(QStringLiteral("importBackup"), QJsonObject{{QStringLiteral("path"), path}});
}

void Bridge::prepareTemplate(const QString &templateID) {
    send("prepareTemplate", QJsonObject{{"template", templateID}});
}

void Bridge::openEditor(const QString &ruleID) {
    if (ruleID.isEmpty()) send("openEditor");
    else send("openEditor", QJsonObject{{"ruleID", ruleID}});
}

void Bridge::acknowledgeCaution(bool hide) {
    send("acknowledgeCaution", QJsonObject{{"hideCaution", hide}});
}

void Bridge::saveRule(const QVariantMap &fields) { send("saveRule", QJsonObject::fromVariantMap(fields)); }

void Bridge::pauseRule(const QString &ruleID) { send("pauseRule", QJsonObject{{"ruleID", ruleID}}); }

void Bridge::resumeRule(const QString &ruleID) { send("resumeRule", QJsonObject{{"ruleID", ruleID}}); }

void Bridge::removeRule(const QString &ruleID, const QString &scope) {
    send("removeRule", QJsonObject{{"ruleID", ruleID}, {"scope", scope}});
}

void Bridge::takeUp(const QString &ruleID) { send("takeUp", QJsonObject{{"ruleID", ruleID}}); }

void Bridge::setAside(const QString &ruleID) { send("setAside", QJsonObject{{"ruleID", ruleID}}); }

void Bridge::setSpiritualFather(const QString &name) {
    send("setSpiritualFather", QJsonObject{{"name", name}});
}

void Bridge::layoutRope(double diameter) {
    if (!(diameter > 0) || diameter > 4096) return;
    m_ropeDiameter = diameter;
    refreshPrayer();
}

QString Bridge::soundPlayer() const {
    if (!m_soundPlayer.isEmpty()) return m_soundPlayer;
    for (const char *name : {"pw-play", "paplay", "aplay"}) {
        const QString path = QStandardPaths::findExecutable(QString::fromLatin1(name));
        if (!path.isEmpty()) return path;
    }
    return {};
}

void Bridge::playSound(const QString &name) {
    QString file;
    if (name == "tick") file = m_tickWav;
    else if (name == "tock") file = m_tockWav;
    else if (name == "bell") file = m_bellWav;
    else return;
    m_lastPlayed = name;
    emit changed();
    if (file.isEmpty() || !QFileInfo::exists(file)) return;
    if (m_soundPlayer.isEmpty()) m_soundPlayer = soundPlayer();
    if (m_soundPlayer.isEmpty()) return;
    auto *playback = new QProcess(this);
    connect(playback, &QProcess::finished, playback, &QObject::deleteLater);
    if (m_soundPlayer.endsWith("aplay")) playback->start(m_soundPlayer, {"-q", file});
    else playback->start(m_soundPlayer, {file});
}

void Bridge::applyPrayer(const QJsonObject &prayer) {
    m_prayerSelection = prayer.value("selection").toString();
    m_prayerRopeAlone = prayer.value("ropeAlone").toBool();
    m_prayerCount = prayer.value("count").toInt();
    m_prayerTarget = prayer.value("target").toInt();
    m_prayerTargets = prayer.value("targets").toArray().toVariantList();
    m_prayerComplete = prayer.value("complete").toBool();
    m_showsRope = prayer.value("showsRope").toBool();
    m_prayerCue = prayer.value("cue").toString();
    m_prayerSound = prayer.contains("sound") ? prayer.value("sound").toString() : QString();
    m_prayerEvent = prayer.value("event").toInt();
    m_prayerDiameter = prayer.value("diameter").toDouble();
    m_prayerDot = prayer.value("dot").toDouble();
    m_prayerBead = prayer.value("bead").toDouble();
    m_prayerKnots = prayer.value("knots").toArray().toVariantList();
    m_prayerBeads = prayer.value("beads").toArray().toVariantList();
    m_prayerChoices = prayer.value("choices").toArray().toVariantList();
    m_prayerWords = prayer.value("words").toArray().toVariantList();
    if (m_prayerDiameter > 0) m_ropeDiameter = m_prayerDiameter;
}

void Bridge::applyOpening(const QJsonObject &opening) {
    m_openingKnots = opening.value("knots").toArray().toVariantList();
    m_openingKnotRadius = opening.value("knotRadius").toDouble();
    m_openingKnotSlots = opening.value("knotSlots").toInt();
    m_openingBox = opening.value("box").toObject().toVariantMap();
    m_openingBars = opening.value("bars").toArray().toVariantList();
    m_openingFootrest = opening.value("footrest").toObject().toVariantMap();
    m_openingBuild = opening.value("build").toDouble();
    m_openingHold = opening.value("hold").toDouble();
    m_openingFade = opening.value("fade").toDouble();
    m_openingKnotFade = opening.value("knotFade").toDouble();
    m_openingStaggerLead = opening.value("staggerLead").toDouble();
    m_openingReady = !m_openingKnots.isEmpty();
}

void Bridge::applyReading(const QJsonObject &reading) {
    m_readingTitle = reading.value("title").toString();
    m_readingSummary = reading.value("summary").toString();
    m_readingSummaryHtml = reading.contains("summaryHtml")
        ? reading.value("summaryHtml").toString() : m_readingSummary;
    m_readingFastNote = reading.value("fastNote").toString();
    m_readingFastNoteHtml = reading.contains("fastNoteHtml")
        ? reading.value("fastNoteHtml").toString() : m_readingFastNote;
    m_readingAbstentionNote = reading.value("abstentionNote").toString();
    m_readingFathers = reading.value("fathersText").toString();
    m_readingFathersBy = reading.value("fathersBy").toString();
    m_readingFooter = reading.value("footer").toString();
    m_readingWaiting = reading.value("waiting").toString();
    m_readingWaitingDetail = reading.value("waitingDetail").toString();
    m_readingSections = reading.value("sections").toArray().toVariantList();
    m_readingMarked = reading.value("marked").toArray().toVariantList();
    m_readingReady = true;
}

void Bridge::applyPsalter(const QJsonObject &psalter) {
    m_psalterSeason = psalter.value("season").toString();
    m_psalterNote = psalter.value("note").toString();
    m_psalterEmpty = psalter.value("empty").toString();
    m_psalterAppointed = psalter.value("appointed").toArray().toVariantList();
    m_psalterManual = psalter.contains("manual") ? psalter.value("manual").toInt() : -1;
    m_psalterManualKathisma = psalter.value("manualKathisma").toObject().toVariantMap();
    m_psalterSource = psalter.value("source").toString();
    m_psalterMarked = psalter.value("marked").toArray().toVariantList();
    m_psalterReady = true;
}

void Bridge::applyLibrary(const QJsonObject &library) {
    m_libraryPage = library.toVariantMap();
    m_libraryReady = true;
}

void Bridge::applyEditor(const QJsonObject &editor) {
    m_editorPage = editor.toVariantMap();
}

void Bridge::applyProgress(const QJsonObject &progress) {
    m_progressHeading = progress.value("heading").toString();
    m_progressThrough = progress.value("through").toString();
    m_progressSummary = progress.value("summary").toArray().toVariantList();
    m_progressRules = progress.value("rules").toArray().toVariantList();
    if (progress.contains("figure")) {
        m_progressFigure = QString::number(progress.value("figure").toInt());
        m_progressFigureNote = progress.value("figureNote").toString();
    } else {
        m_progressFigure.clear();
        m_progressFigureNote.clear();
    }
    m_progressReady = true;
}

void Bridge::applyGlossary(const QJsonObject &glossary) {
    m_glossaryNote = glossary.value("note").toString();
    m_glossaryQuery = glossary.value("query").toString();
    m_glossaryCategories = glossary.value("categories").toArray().toVariantList();
    if (glossary.contains("entry"))
        m_glossaryEntry = glossary.value("entry").toObject().toVariantMap();
    else
        m_glossaryEntry.clear();
    m_glossaryReady = true;
}

void Bridge::applySettings(const QJsonObject &settings) {
    m_settings = settings.toVariantMap();
    m_settingsReady = true;
    if (settings.contains(QStringLiteral("reducedMotion")))
        m_reducedMotion = settings.value(QStringLiteral("reducedMotion")).toBool();
}

void Bridge::applyTones(const QJsonObject &tones) {
    m_tickWav = tones.value("tick").toString();
    m_tockWav = tones.value("tock").toString();
    m_bellWav = tones.value("bell").toString();
}

int Bridge::newestAcceptedId() const {
    return std::max({m_newestSuccessId, m_newestPrayerId, m_newestOpeningId, m_newestToneId,
                     m_newestReadingId, m_newestPsalterId, m_newestLibraryId, m_newestProgressId,
                     m_newestGlossaryId, m_newestSettingsId, m_newestMotionId});
}

void Bridge::readResponses() {
    m_pending += m_process.readAllStandardOutput();
    qsizetype newline;
    while ((newline = m_pending.indexOf('\n')) >= 0) {
        const QByteArray line = m_pending.left(newline);
        m_pending.remove(0, newline + 1);
        const QJsonDocument document = QJsonDocument::fromJson(line);
        if (!document.isObject()) {
            m_error = "The Swift helper sent an invalid response.";
            emit changed();
            continue;
        }
        const BridgeResponse response = decodeResponse(document.object());
        if (response.version != protocolVersion) {
            m_error = "The Linux interface and Swift helper use different protocol versions.";
            emit changed();
            continue;
        }
        // A reply for an earlier request must not wipe a newer success, and an
        // error must not blank the snapshot the newer success already showed.
        if (!response.ok) {
            // A late error must not replace a success that was already shown,
            // whether that success was the day or the rope.
            if (response.id > newestAcceptedId()) {
                m_error = response.error;
                emit changed();
            }
            continue;
        }
        if (response.hasMode) {
            m_connected = true;
            m_status = "Ready";
            m_restarts = 0;
            if (response.id >= m_newestSuccessId) m_error.clear();
        }
        // Prayer replies and day snapshots travel on one socket but they are
        // different documents. A rope count that returns first must not throw
        // away the day's snapshot, and a snapshot must not throw away the count.
        if (response.hasPrayer && response.id >= m_newestPrayerId) {
            m_newestPrayerId = response.id;
            applyPrayer(response.prayer);
            m_error.clear();
        }
        if (response.hasOpening && response.id >= m_newestOpeningId) {
            m_newestOpeningId = response.id;
            applyOpening(response.opening);
            m_error.clear();
        }
        if (response.hasTones && response.id >= m_newestToneId) {
            m_newestToneId = response.id;
            applyTones(response.tones);
            m_error.clear();
        }
        if (response.hasReading && response.id >= m_newestReadingId) {
            m_newestReadingId = response.id;
            applyReading(response.reading);
            m_error.clear();
        }
        if (response.hasPsalter && response.id >= m_newestPsalterId) {
            m_newestPsalterId = response.id;
            applyPsalter(response.psalter);
            m_error.clear();
        }
        if ((response.hasLibrary || response.hasEditor) && response.id >= m_newestLibraryId) {
            m_newestLibraryId = response.id;
            if (response.hasLibrary) applyLibrary(response.library);
            if (response.hasEditor) applyEditor(response.editor);
            m_error.clear();
        }
        if (response.hasProgress && response.id >= m_newestProgressId) {
            m_newestProgressId = response.id;
            applyProgress(response.progress);
            m_error.clear();
        }
        // A glossary reply is a domain payload. It must not be treated as a day,
        // and a missing entry must clear the one a previous term had open.
        if (response.hasGlossary && response.id >= m_newestGlossaryId) {
            m_newestGlossaryId = response.id;
            applyGlossary(response.glossary);
            m_error.clear();
        }
        // Settings are not a day. A read or an export must not be treated as one.
        // Reduced motion is stored with the record, so the snapshot after a
        // helper restart carries it on its own.
        if (response.hasSettings && response.id >= m_newestSettingsId) {
            m_newestSettingsId = response.id;
            applySettings(response.settings);
            m_error.clear();
        }
        if (response.hasReducedMotion && response.id >= m_newestMotionId) {
            m_newestMotionId = response.id;
            m_reducedMotion = response.reducedMotion;
            ++m_motionEvent;
            m_error.clear();
        }
        if (!response.home || response.id < m_newestSuccessId) {
            emit changed();
            continue;
        }
        m_newestSuccessId = response.id;
        m_error.clear();
        if (response.hasDisplayName) m_displayName = response.displayName;
        if (response.hasToday) m_today = response.today;
        if (response.hasSelectedDate) {
            m_snapshotReady = true;
            m_selectedDate = response.selectedDate;
            const QDate date = QDate::fromString(m_selectedDate, Qt::ISODate);
            m_artworkUrl.clear();
            if (date.isValid() && !m_artworkOrder.isEmpty()) {
                const QString name = m_artworkOrder.at(date.dayOfYear() % m_artworkOrder.size());
                const QString path = QDir(m_artworkRoot).filePath(name);
                if (QFileInfo::exists(path)) m_artworkUrl = QUrl::fromLocalFile(path).toString();
            }
        }
        if (response.hasDayTitle) m_dayTitle = response.dayTitle;
        if (response.hasObservedDate) m_observedDate = response.observedDate;
        if (response.hasShowOldStyleDates) m_showOldStyleDates = response.showOldStyleDates;
        if (response.hasSayingText) m_sayingText = response.sayingText;
        if (response.hasSayingAuthor) m_sayingAuthor = response.sayingAuthor;
        if (response.hasSayingSource) m_sayingSource = response.sayingSource;
        if (response.hasEntries) m_entries = response.entries;
        if (response.hasWeek) m_week = response.week;
        if (response.hasPsalmOneVerses) m_psalmOneVerses = response.psalmOneVerses;
        if (response.hasNeedsWelcome) m_needsWelcome = response.needsWelcome;
        // A day snapshot omits todayLink when the selected day is today.
        // Thanksgiving is a single event: a later snapshot that leaves the key
        // out must not wipe the line already on screen.
        if (response.hasWeek || response.hasEntries) {
            m_todayLink = response.hasTodayLink ? response.todayLink : QString();
        }
        if (response.hasThanksgiving) {
            m_thanksgiving = response.thanksgiving;
            ++m_thanksEvent;
        }
        emit changed();
    }
}
