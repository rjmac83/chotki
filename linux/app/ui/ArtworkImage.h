#pragma once

#include <QImage>
#include <QQuickPaintedItem>
#include <QUrl>

class ArtworkImage : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool drifting READ drifting WRITE setDrifting NOTIFY driftingChanged)
    Q_PROPERTY(qreal progress READ progress WRITE setProgress NOTIFY progressChanged)

public:
    explicit ArtworkImage(QQuickItem *parent = nullptr);
    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);
    bool drifting() const { return m_drifting; }
    void setDrifting(bool drifting);
    qreal progress() const { return m_progress; }
    void setProgress(qreal progress);
    void paint(QPainter *painter) override;

signals:
    void sourceChanged();
    void driftingChanged();
    void progressChanged();

private:
    QUrl m_source;
    QImage m_image;
    bool m_drifting = false;
    qreal m_progress = 1;
    qreal m_focusX = 0.5;
    qreal m_focusY = 0.45;
    int m_number = 0;
};
