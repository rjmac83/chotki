#include "ArtworkImage.h"
#include "SayingFocus.h"

#include <QImageReader>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>

#include <algorithm>
#include <cmath>

ArtworkImage::ArtworkImage(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
}

void ArtworkImage::setSource(const QUrl &source) {
    if (m_source == source) return;
    m_source = source;
    m_image = {};
    m_focusX = 0.5;
    m_focusY = 0.45;
    m_number = 0;
    if (source.isLocalFile()) {
        QImageReader reader(source.toLocalFile());
        reader.setAutoTransform(true);
        m_image = reader.read();
        const SayingFocus focus = sayingFocusForFile(source.toLocalFile());
        m_focusX = focus.x;
        m_focusY = focus.y;
        m_number = focus.number;
    }
    emit sourceChanged();
    update();
}

void ArtworkImage::setDrifting(bool drifting) {
    if (m_drifting == drifting) return;
    m_drifting = drifting;
    emit driftingChanged();
    update();
}

void ArtworkImage::setProgress(qreal progress) {
    const qreal clamped = std::clamp(progress, 0.0, 1.0);
    if (std::abs(m_progress - clamped) < 0.0001) return;
    m_progress = clamped;
    emit progressChanged();
    update();
}

void ArtworkImage::paint(QPainter *painter) {
    if (m_image.isNull() || width() <= 0 || height() <= 0) return;
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    QPainterPath rounded;
    rounded.addRoundedRect(QRectF(0, 0, width(), height()), 20, 20);
    painter->setClipPath(rounded);

    qreal scale = std::max(width() / m_image.width(), height() / m_image.height());
    qreal originX = (width() - m_image.width() * scale) / 2;
    qreal originY = (height() - m_image.height() * scale) / 2;
    if (!m_drifting) {
        // ProgressTabView pins the top of the icon. A centre crop on a wide
        // strip cuts the halos off. If the pane is too short to keep the
        // faces at a width-covering scale, zoom out until that band fits.
        const qreal faceLimit = height() / (m_image.height() * progressFaceBand());
        if (scale > faceLimit) scale = faceLimit;
        originX = (width() - m_image.width() * scale) / 2;
        originY = 0;
    }
    if (m_drifting) {
        // The same overscan and rest point as DriftingArtwork. Progress 1
        // is the curated crop, and it is where a review grab and reduced
        // motion stay.
        scale *= 1.08;
        const qreal renderedWidth = m_image.width() * scale;
        const qreal renderedHeight = m_image.height() * scale;
        const qreal lowerX = width() - renderedWidth;
        const qreal lowerY = height() - renderedHeight;
        const qreal restX = std::min(0.0, std::max(lowerX, width() * 0.5 - m_focusX * renderedWidth));
        const qreal restY = std::min(0.0, std::max(lowerY, height() * 0.4 - m_focusY * renderedHeight));
        const double xSign = m_number % 2 == 0 ? 1.0 : -1.0;
        const double ySign = m_number % 3 == 0 ? 1.0 : -1.0;
        const qreal startX = sayingPanNearby(restX, lowerX, 0, 14, xSign);
        const qreal startY = sayingPanNearby(restY, lowerY, 0, 18, ySign);
        originX = startX + (restX - startX) * m_progress;
        originY = startY + (restY - startY) * m_progress;
    }
    if (std::abs(m_paintedScale - scale) > 0.0001 || std::abs(m_paintedOriginY - originY) > 0.0001) {
        m_paintedScale = scale;
        m_paintedOriginY = originY;
        emit painted();
    }
    painter->drawImage(QRectF(originX, originY, m_image.width() * scale, m_image.height() * scale), m_image);

    QLinearGradient shade(0, 0, 0, height());
    if (m_drifting) {
        shade.setColorAt(0.2, QColor(0, 0, 0, 0));
        shade.setColorAt(1, QColor(0, 0, 0, 217));
    } else {
        shade.setColorAt(0, QColor(0, 0, 0, 0));
        shade.setColorAt(0.58, QColor(0, 0, 0, 66));
        shade.setColorAt(1, QColor(0, 0, 0, 224));
    }
    painter->fillRect(QRectF(0, 0, width(), height()), shade);
}
