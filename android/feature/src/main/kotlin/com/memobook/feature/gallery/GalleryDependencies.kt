package com.memobook.feature.gallery

import com.memobook.feature.AppDependencies
import com.memobook.feature.ContentCache

/**
 * La galerie des carnets de la communauté, servie par `GET /v1/gallery`.
 * Jumeau de `AppDependencies.galleryModel()` (`AppDependencies.swift`).
 */
fun AppDependencies.galleryModel(): GalleryModel = GalleryModel(
    source = cachedSource(ContentCache.Slot.Gallery) { api.gallery() },
    cached = cached(ContentCache.Slot.Gallery),
)
