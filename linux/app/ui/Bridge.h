#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class Bridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(bool review READ review NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString displayName READ displayName NOTIFY changed)
    Q_PROPERTY(QString today READ today NOTIFY changed)
    Q_PROPERTY(QString selectedDate READ selectedDate NOTIFY changed)
    Q_PROPERTY(QString dayTitle READ dayTitle NOTIFY changed)
    Q_PROPERTY(QString observedDate READ observedDate NOTIFY changed)
    Q_PROPERTY(bool showOldStyleDates READ showOldStyleDates NOTIFY changed)
    Q_PROPERTY(QString sayingText READ sayingText NOTIFY changed)
    Q_PROPERTY(QString sayingAuthor READ sayingAuthor NOTIFY changed)
    Q_PROPERTY(QString sayingSource READ sayingSource NOTIFY changed)
    Q_PROPERTY(QString artworkUrl READ artworkUrl NOTIFY changed)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    Q_PROPERTY(QVariantList week READ week NOTIFY changed)
    Q_PROPERTY(int psalmOneVerses READ psalmOneVerses NOTIFY changed)
    Q_PROPERTY(QString prayerSelection READ prayerSelection NOTIFY changed)
    Q_PROPERTY(bool prayerRopeAlone READ prayerRopeAlone NOTIFY changed)
    Q_PROPERTY(int prayerCount READ prayerCount NOTIFY changed)
    Q_PROPERTY(int prayerTarget READ prayerTarget NOTIFY changed)
    Q_PROPERTY(QVariantList prayerTargets READ prayerTargets NOTIFY changed)
    Q_PROPERTY(bool prayerComplete READ prayerComplete NOTIFY changed)
    Q_PROPERTY(bool showsRope READ showsRope NOTIFY changed)
    Q_PROPERTY(QString prayerCue READ prayerCue NOTIFY changed)
    Q_PROPERTY(QString prayerSound READ prayerSound NOTIFY changed)
    Q_PROPERTY(int prayerEvent READ prayerEvent NOTIFY changed)
    Q_PROPERTY(double prayerDiameter READ prayerDiameter NOTIFY changed)
    Q_PROPERTY(double prayerDot READ prayerDot NOTIFY changed)
    Q_PROPERTY(double prayerBead READ prayerBead NOTIFY changed)
    Q_PROPERTY(QVariantList prayerKnots READ prayerKnots NOTIFY changed)
    Q_PROPERTY(QVariantList prayerBeads READ prayerBeads NOTIFY changed)
    Q_PROPERTY(QVariantList prayerChoices READ prayerChoices NOTIFY changed)
    Q_PROPERTY(QVariantList prayerWords READ prayerWords NOTIFY changed)
    Q_PROPERTY(bool openingReady READ openingReady NOTIFY changed)
    Q_PROPERTY(QVariantList openingKnots READ openingKnots NOTIFY changed)
    Q_PROPERTY(double openingKnotRadius READ openingKnotRadius NOTIFY changed)
    Q_PROPERTY(int openingKnotSlots READ openingKnotSlots NOTIFY changed)
    Q_PROPERTY(QVariantMap openingBox READ openingBox NOTIFY changed)
    Q_PROPERTY(QVariantList openingBars READ openingBars NOTIFY changed)
    Q_PROPERTY(QVariantMap openingFootrest READ openingFootrest NOTIFY changed)
    Q_PROPERTY(double openingBuild READ openingBuild NOTIFY changed)
    Q_PROPERTY(double openingHold READ openingHold NOTIFY changed)
    Q_PROPERTY(double openingFade READ openingFade NOTIFY changed)
    Q_PROPERTY(double openingKnotFade READ openingKnotFade NOTIFY changed)
    Q_PROPERTY(double openingStaggerLead READ openingStaggerLead NOTIFY changed)
    Q_PROPERTY(QString lastPlayed READ lastPlayed NOTIFY changed)
    Q_PROPERTY(bool readingReady READ readingReady NOTIFY changed)
    Q_PROPERTY(QString readingTitle READ readingTitle NOTIFY changed)
    Q_PROPERTY(QString readingSummary READ readingSummary NOTIFY changed)
    Q_PROPERTY(QString readingSummaryHtml READ readingSummaryHtml NOTIFY changed)
    Q_PROPERTY(QString readingFastNote READ readingFastNote NOTIFY changed)
    Q_PROPERTY(QString readingFastNoteHtml READ readingFastNoteHtml NOTIFY changed)
    Q_PROPERTY(QString readingAbstentionNote READ readingAbstentionNote NOTIFY changed)
    Q_PROPERTY(QString readingFathers READ readingFathers NOTIFY changed)
    Q_PROPERTY(QString readingFathersBy READ readingFathersBy NOTIFY changed)
    Q_PROPERTY(QString readingFooter READ readingFooter NOTIFY changed)
    Q_PROPERTY(QString readingWaiting READ readingWaiting NOTIFY changed)
    Q_PROPERTY(QString readingWaitingDetail READ readingWaitingDetail NOTIFY changed)
    Q_PROPERTY(QVariantList readingSections READ readingSections NOTIFY changed)
    Q_PROPERTY(QVariantList readingMarked READ readingMarked NOTIFY changed)
    Q_PROPERTY(bool psalterReady READ psalterReady NOTIFY changed)
    Q_PROPERTY(QString psalterSeason READ psalterSeason NOTIFY changed)
    Q_PROPERTY(QString psalterNote READ psalterNote NOTIFY changed)
    Q_PROPERTY(QString psalterEmpty READ psalterEmpty NOTIFY changed)
    Q_PROPERTY(QVariantList psalterAppointed READ psalterAppointed NOTIFY changed)
    Q_PROPERTY(int psalterManual READ psalterManual NOTIFY changed)
    Q_PROPERTY(QVariantMap psalterManualKathisma READ psalterManualKathisma NOTIFY changed)
    Q_PROPERTY(QString psalterSource READ psalterSource NOTIFY changed)
    Q_PROPERTY(QVariantList psalterMarked READ psalterMarked NOTIFY changed)
    Q_PROPERTY(bool libraryReady READ libraryReady NOTIFY changed)
    Q_PROPERTY(QVariantMap libraryPage READ libraryPage NOTIFY changed)
    Q_PROPERTY(QVariantMap editorPage READ editorPage NOTIFY changed)
    Q_PROPERTY(QString todayLink READ todayLink NOTIFY changed)
    Q_PROPERTY(QString thanksgiving READ thanksgiving NOTIFY changed)
    Q_PROPERTY(int thanksEvent READ thanksEvent NOTIFY changed)
    Q_PROPERTY(bool progressReady READ progressReady NOTIFY changed)
    Q_PROPERTY(QString progressHeading READ progressHeading NOTIFY changed)
    Q_PROPERTY(QString progressThrough READ progressThrough NOTIFY changed)
    Q_PROPERTY(QVariantList progressSummary READ progressSummary NOTIFY changed)
    Q_PROPERTY(QVariantList progressRules READ progressRules NOTIFY changed)
    Q_PROPERTY(QString progressFigure READ progressFigure NOTIFY changed)
    Q_PROPERTY(QString progressFigureNote READ progressFigureNote NOTIFY changed)
    Q_PROPERTY(QString progressArtworkUrl READ progressArtworkUrl NOTIFY changed)
    Q_PROPERTY(bool glossaryReady READ glossaryReady NOTIFY changed)
    Q_PROPERTY(QString glossaryNote READ glossaryNote NOTIFY changed)
    Q_PROPERTY(QString glossaryQuery READ glossaryQuery NOTIFY changed)
    Q_PROPERTY(QVariantList glossaryCategories READ glossaryCategories NOTIFY changed)
    Q_PROPERTY(QVariantMap glossaryEntry READ glossaryEntry NOTIFY changed)
    Q_PROPERTY(bool needsWelcome READ needsWelcome NOTIFY changed)
    Q_PROPERTY(bool reducedMotion READ reducedMotion NOTIFY changed)
    Q_PROPERTY(int motionEvent READ motionEvent NOTIFY changed)
    Q_PROPERTY(bool settingsReady READ settingsReady NOTIFY changed)
    Q_PROPERTY(QVariantMap settings READ settings NOTIFY changed)

public:
    Bridge(QString program, bool review, QObject *parent = nullptr);
    ~Bridge() override;

    bool connected() const { return m_connected; }
    bool review() const { return m_review; }
    QString status() const { return m_status; }
    QString error() const { return m_error; }
    QString displayName() const { return m_displayName; }
    QString today() const { return m_today; }
    QString selectedDate() const { return m_selectedDate; }
    QString dayTitle() const { return m_dayTitle; }
    QString observedDate() const { return m_observedDate; }
    bool showOldStyleDates() const { return m_showOldStyleDates; }
    QString sayingText() const { return m_sayingText; }
    QString sayingAuthor() const { return m_sayingAuthor; }
    QString sayingSource() const { return m_sayingSource; }
    QString artworkUrl() const { return m_artworkUrl; }
    QVariantList entries() const { return m_entries; }
    QVariantList week() const { return m_week; }
    int psalmOneVerses() const { return m_psalmOneVerses; }
    QString prayerSelection() const { return m_prayerSelection; }
    bool prayerRopeAlone() const { return m_prayerRopeAlone; }
    int prayerCount() const { return m_prayerCount; }
    int prayerTarget() const { return m_prayerTarget; }
    QVariantList prayerTargets() const { return m_prayerTargets; }
    bool prayerComplete() const { return m_prayerComplete; }
    bool showsRope() const { return m_showsRope; }
    QString prayerCue() const { return m_prayerCue; }
    QString prayerSound() const { return m_prayerSound; }
    int prayerEvent() const { return m_prayerEvent; }
    double prayerDiameter() const { return m_prayerDiameter; }
    double prayerDot() const { return m_prayerDot; }
    double prayerBead() const { return m_prayerBead; }
    QVariantList prayerKnots() const { return m_prayerKnots; }
    QVariantList prayerBeads() const { return m_prayerBeads; }
    QVariantList prayerChoices() const { return m_prayerChoices; }
    QVariantList prayerWords() const { return m_prayerWords; }
    bool openingReady() const { return m_openingReady; }
    QVariantList openingKnots() const { return m_openingKnots; }
    double openingKnotRadius() const { return m_openingKnotRadius; }
    int openingKnotSlots() const { return m_openingKnotSlots; }
    QVariantMap openingBox() const { return m_openingBox; }
    QVariantList openingBars() const { return m_openingBars; }
    QVariantMap openingFootrest() const { return m_openingFootrest; }
    double openingBuild() const { return m_openingBuild; }
    double openingHold() const { return m_openingHold; }
    double openingFade() const { return m_openingFade; }
    double openingKnotFade() const { return m_openingKnotFade; }
    double openingStaggerLead() const { return m_openingStaggerLead; }
    QString lastPlayed() const { return m_lastPlayed; }
    bool readingReady() const { return m_readingReady; }
    QString readingTitle() const { return m_readingTitle; }
    QString readingSummary() const { return m_readingSummary; }
    QString readingSummaryHtml() const { return m_readingSummaryHtml; }
    QString readingFastNote() const { return m_readingFastNote; }
    QString readingFastNoteHtml() const { return m_readingFastNoteHtml; }
    QString readingAbstentionNote() const { return m_readingAbstentionNote; }
    QString readingFathers() const { return m_readingFathers; }
    QString readingFathersBy() const { return m_readingFathersBy; }
    QString readingFooter() const { return m_readingFooter; }
    QString readingWaiting() const { return m_readingWaiting; }
    QString readingWaitingDetail() const { return m_readingWaitingDetail; }
    QVariantList readingSections() const { return m_readingSections; }
    QVariantList readingMarked() const { return m_readingMarked; }
    bool psalterReady() const { return m_psalterReady; }
    QString psalterSeason() const { return m_psalterSeason; }
    QString psalterNote() const { return m_psalterNote; }
    QString psalterEmpty() const { return m_psalterEmpty; }
    QVariantList psalterAppointed() const { return m_psalterAppointed; }
    int psalterManual() const { return m_psalterManual; }
    QVariantMap psalterManualKathisma() const { return m_psalterManualKathisma; }
    QString psalterSource() const { return m_psalterSource; }
    QVariantList psalterMarked() const { return m_psalterMarked; }
    bool libraryReady() const { return m_libraryReady; }
    QVariantMap libraryPage() const { return m_libraryPage; }
    QVariantMap editorPage() const { return m_editorPage; }
    QString todayLink() const { return m_todayLink; }
    QString thanksgiving() const { return m_thanksgiving; }
    int thanksEvent() const { return m_thanksEvent; }
    bool progressReady() const { return m_progressReady; }
    QString progressHeading() const { return m_progressHeading; }
    QString progressThrough() const { return m_progressThrough; }
    QVariantList progressSummary() const { return m_progressSummary; }
    QVariantList progressRules() const { return m_progressRules; }
    QString progressFigure() const { return m_progressFigure; }
    QString progressFigureNote() const { return m_progressFigureNote; }
    QString progressArtworkUrl() const { return m_progressArtworkUrl; }
    bool glossaryReady() const { return m_glossaryReady; }
    QString glossaryNote() const { return m_glossaryNote; }
    QString glossaryQuery() const { return m_glossaryQuery; }
    QVariantList glossaryCategories() const { return m_glossaryCategories; }
    QVariantMap glossaryEntry() const { return m_glossaryEntry; }
    bool needsWelcome() const { return m_needsWelcome; }
    bool reducedMotion() const { return m_reducedMotion; }
    int motionEvent() const { return m_motionEvent; }
    bool settingsReady() const { return m_settingsReady; }
    QVariantMap settings() const { return m_settings; }

    bool snapshotReady() const { return m_snapshotReady; }
    qint64 helperProcessId() const { return m_process.processId(); }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setReviewName(const QString &name);
    Q_INVOKABLE void selectDate(const QString &date);
    Q_INVOKABLE void toggleKept(const QString &ruleID);
    Q_INVOKABLE void markKeptLate(const QString &ruleID);
    Q_INVOKABLE void standDownDay(const QString &ruleID);
    Q_INVOKABLE void shiftWeek(int direction);
    Q_INVOKABLE void refreshPrayer();
    Q_INVOKABLE void choosePrayer(const QString &selection);
    Q_INVOKABLE void advancePrayer();
    Q_INVOKABLE void advancePrayerAt(double now);
    Q_INVOKABLE void aimPrayer(int target);
    Q_INVOKABLE void showRope(bool shown);
    Q_INVOKABLE void startAgain();
    Q_INVOKABLE void layoutRope(double diameter);
    Q_INVOKABLE void playSound(const QString &name);
    Q_INVOKABLE void showReading();
    Q_INVOKABLE void showProgress();
    Q_INVOKABLE void showGlossary(const QString &slug, const QString &query);
    Q_INVOKABLE void showSettings();
    Q_INVOKABLE void saveSettings(const QVariantMap &fields);
    Q_INVOKABLE void exportBackup(const QString &path);
    Q_INVOKABLE void importBackup(const QString &path);
    Q_INVOKABLE void openReading(int band);
    Q_INVOKABLE void toggleReading(int band);
    Q_INVOKABLE void finishReading(int band);
    Q_INVOKABLE void refreshPsalter();
    Q_INVOKABLE void openKathisma(int number, bool manual);
    Q_INVOKABLE void finishPsalter();
    Q_INVOKABLE void showLibrary(const QString &query);
    Q_INVOKABLE void prepareTemplate(const QString &templateID);
    Q_INVOKABLE void openEditor(const QString &ruleID);
    Q_INVOKABLE void acknowledgeCaution(bool hide);
    Q_INVOKABLE void saveRule(const QVariantMap &fields);
    Q_INVOKABLE void pauseRule(const QString &ruleID);
    Q_INVOKABLE void resumeRule(const QString &ruleID);
    Q_INVOKABLE void removeRule(const QString &ruleID, const QString &scope);
    Q_INVOKABLE void takeUp(const QString &ruleID);
    Q_INVOKABLE void setAside(const QString &ruleID);
    Q_INVOKABLE void setSpiritualFather(const QString &name);

signals:
    void changed();

private:
    void start();
    void send(const QString &operation, const QJsonObject &fields = {});
    void readResponses();
    void stopped();
    void applyPrayer(const QJsonObject &prayer);
    void applyOpening(const QJsonObject &opening);
    void applyTones(const QJsonObject &tones);
    void applyReading(const QJsonObject &reading);
    void applyPsalter(const QJsonObject &psalter);
    void applyLibrary(const QJsonObject &library);
    void applyEditor(const QJsonObject &editor);
    void applyProgress(const QJsonObject &progress);
    void applyGlossary(const QJsonObject &glossary);
    void applySettings(const QJsonObject &settings);
    QString soundPlayer() const;
    int newestAcceptedId() const;

    static constexpr int protocolVersion = 1;
    QProcess m_process;
    QString m_program;
    QByteArray m_pending;
    int m_nextId = 1;
    int m_newestSuccessId = -1;
    int m_newestPrayerId = -1;
    int m_newestOpeningId = -1;
    int m_newestToneId = -1;
    int m_newestReadingId = -1;
    int m_newestPsalterId = -1;
    int m_newestLibraryId = -1;
    int m_newestProgressId = -1;
    int m_newestGlossaryId = -1;
    int m_newestSettingsId = -1;
    int m_newestMotionId = -1;
    double m_ropeDiameter = 240;
    int m_restarts = 0;
    bool m_snapshotReady = false;
    bool m_review;
    bool m_closing = false;
    bool m_connected = false;
    QString m_status = "Connecting to the record…";
    QString m_error;
    QString m_displayName;
    QString m_today;
    QString m_selectedDate;
    QString m_dayTitle;
    QString m_observedDate;
    bool m_showOldStyleDates = false;
    QString m_sayingText;
    QString m_sayingAuthor;
    QString m_sayingSource;
    QString m_artworkRoot;
    QString m_artworkUrl;
    QStringList m_artworkOrder;
    QVariantList m_entries;
    QVariantList m_week;
    int m_psalmOneVerses = 0;
    QString m_prayerSelection = "jesus-prayer";
    bool m_prayerRopeAlone = false;
    int m_prayerCount = 0;
    int m_prayerTarget = 33;
    QVariantList m_prayerTargets;
    bool m_prayerComplete = false;
    bool m_showsRope = true;
    QString m_prayerCue;
    QString m_prayerSound;
    int m_prayerEvent = 0;
    double m_prayerDiameter = 240;
    double m_prayerDot = 11;
    double m_prayerBead = 15.4;
    QVariantList m_prayerKnots;
    QVariantList m_prayerBeads;
    QVariantList m_prayerChoices;
    QVariantList m_prayerWords;
    bool m_openingReady = false;
    QVariantList m_openingKnots;
    double m_openingKnotRadius = 0;
    int m_openingKnotSlots = 12;
    QVariantMap m_openingBox;
    QVariantList m_openingBars;
    QVariantMap m_openingFootrest;
    double m_openingBuild = 1.8;
    double m_openingHold = 1.5;
    double m_openingFade = 0.4;
    double m_openingKnotFade = 0.16;
    double m_openingStaggerLead = 0.2;
    QString m_tickWav;
    QString m_tockWav;
    QString m_bellWav;
    QString m_lastPlayed;
    QString m_soundPlayer;
    bool m_readingReady = false;
    QString m_readingTitle;
    QString m_readingSummary;
    QString m_readingSummaryHtml;
    QString m_readingFastNote;
    QString m_readingFastNoteHtml;
    QString m_readingAbstentionNote;
    QString m_readingFathers;
    QString m_readingFathersBy;
    QString m_readingFooter;
    QString m_readingWaiting;
    QString m_readingWaitingDetail;
    QVariantList m_readingSections;
    QVariantList m_readingMarked;
    bool m_psalterReady = false;
    QString m_psalterSeason;
    QString m_psalterNote;
    QString m_psalterEmpty;
    QVariantList m_psalterAppointed;
    int m_psalterManual = -1;
    QVariantMap m_psalterManualKathisma;
    QString m_psalterSource;
    QVariantList m_psalterMarked;
    bool m_libraryReady = false;
    QVariantMap m_libraryPage;
    QVariantMap m_editorPage;
    QString m_todayLink;
    QString m_thanksgiving;
    int m_thanksEvent = 0;
    bool m_progressReady = false;
    QString m_progressHeading;
    QString m_progressThrough;
    QVariantList m_progressSummary;
    QVariantList m_progressRules;
    QString m_progressFigure;
    QString m_progressFigureNote;
    QString m_progressArtworkUrl;
    bool m_glossaryReady = false;
    QString m_glossaryNote;
    QString m_glossaryQuery;
    QVariantList m_glossaryCategories;
    QVariantMap m_glossaryEntry;
    bool m_needsWelcome = false;
    bool m_reducedMotion = false;
    int m_motionEvent = 0;
    bool m_settingsReady = false;
    QVariantMap m_settings;
};
