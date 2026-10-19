package com.dynops.bcwms

/**
 * Kitoko (19 Eki 2026) BADE hattının kopyasıdır: BADE'nin terminal oturumu,
 * palet/LP iş akışları ve güncelleme davranışı Kitoko'da da geçerlidir.
 * Marka/logo ve kiracı ayarları flavor'a özel kalır (CompanyBrand, build.gradle).
 */
fun isBadeFamily(flavor: String = BuildConfig.FLAVOR): Boolean =
    flavor.equals("bade", ignoreCase = true) || flavor.equals("kitoko", ignoreCase = true)
