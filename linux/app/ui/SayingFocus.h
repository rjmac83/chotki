#pragma once

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <cmath>

// The hand-reviewed points in macos/.../SayingPanFocus.swift. Numbers 1–42
// are that table. Later images fall back to approved-sources.json beside the
// file, then to the same default (0.5, 0.45). The day's saying uses this.
// Progress artwork does not.

struct SayingFocus {
    double x = 0.5;
    double y = 0.45;
    int number = 0;
};

inline SayingFocus sayingFocusForFile(const QString &path) {
    SayingFocus focus;
    const QFileInfo info(path);
    focus.number = info.baseName().toInt();
    static const double xs[43] = {
        0,    0.60, 0.67, 0.50, 0.50, 0.52, 0.46, 0.51, 0.50, 0.51, 0.50,
        0.50, 0.65, 0.32, 0.50, 0.52, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50,
        0.50, 0.50, 0.50, 0.50, 0.50, 0.52, 0.50, 0.50, 0.50, 0.50, 0.50,
        0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50
    };
    static const double ys[43] = {
        0,    0.41, 0.40, 0.30, 0.46, 0.48, 0.39, 0.53, 0.33, 0.39, 0.47,
        0.34, 0.18, 0.16, 0.43, 0.44, 0.43, 0.37, 0.47, 0.48, 0.27, 0.48,
        0.25, 0.35, 0.49, 0.45, 0.23, 0.19, 0.31, 0.30, 0.49, 0.31, 0.41,
        0.43, 0.47, 0.48, 0.40, 0.50, 0.50, 0.45, 0.49, 0.27, 0.29
    };
    if (focus.number >= 1 && focus.number <= 42) {
        focus.x = xs[focus.number];
        focus.y = ys[focus.number];
        return focus;
    }
    QFile file(info.dir().filePath(QStringLiteral("approved-sources.json")));
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonArray sources = QJsonDocument::fromJson(file.readAll()).array();
        for (const QJsonValue &value : sources) {
            const QJsonObject source = value.toObject();
            if (source.value(QStringLiteral("number")).toInt() != focus.number) continue;
            focus.x = source.value(QStringLiteral("focusX")).toDouble(0.5);
            focus.y = source.value(QStringLiteral("focusY")).toDouble(0.45);
            return focus;
        }
    }
    return focus;
}

inline double sayingPanNearby(double end, double lower, double upper, double travel, double sign) {
    const double preferredRoom = sign > 0 ? upper - end : end - lower;
    const double oppositeRoom = sign > 0 ? end - lower : upper - end;
    const double direction = preferredRoom >= std::min(travel, oppositeRoom) ? sign : -sign;
    return std::min(upper, std::max(lower, end + direction * travel));
}
