#pragma once

#include <QImage>
#include <QQuickPaintedItem>
#include <QUrl>

class ArtworkImage : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool drifting READ drifting WRITE setDrifting NOTIFY driftingChanged)
    Q_PROPERTY(qreal progress READ progress WRITE setProgress NOTIFY progressChanged)
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY sourceChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY sourceChanged)
    // Halos and faces in progress.jpg. A cover crop that starts lower, or
    // zooms past this band, hides the saints' heads.
    Q_PROPERTY(qreal progressFaceBand READ progressFaceBand CONSTANT)
    Q_PROPERTY(qreal paintedOriginY READ paintedOriginY NOTIFY painted)
    Q_PROPERTY(qreal paintedScale READ paintedScale NOTIFY painted)

public:
    explicit ArtworkImage(QQuickItem *parent = nullptr);
    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);
    bool drifting() const { return m_drifting; }
    void setDrifting(bool drifting);
    qreal progress() const { return m_progress; }
    void setProgress(qreal progress);
    int imageWidth() const { return m_image.width(); }
    int imageHeight() const { return m_image.height(); }
    static qreal progressFaceBand() { return 0.40; }
    qreal paintedOriginY() const { return m_paintedOriginY; }
    qreal paintedScale() const { return m_paintedScale; }
    void paint(QPainter *painter) override;

signals:
    void sourceChanged();
    void driftingChanged();
    void progressChanged();
    void painted();

private:
    QUrl m_source;
    QImage m_image;
    bool m_drifting = false;
    qreal m_progress = 1;
    qreal m_focusX = 0.5;
    qreal m_focusY = 0.45;
    int m_number = 0;
    qreal m_paintedOriginY = 0;
    qreal m_paintedScale = 0;
};
