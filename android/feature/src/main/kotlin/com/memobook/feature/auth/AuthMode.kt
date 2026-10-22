package com.memobook.feature.auth

/** Les deux faces de l'écran d'entrée. Jumeau de `AuthMode.swift`. */
enum class AuthMode {
    SignUp,
    SignIn,
    ;

    val segmentTitle: String
        get() = when (this) {
            SignUp -> "Inscription"
            SignIn -> "Connexion"
        }

    val title: String
        get() = when (this) {
            SignUp -> "Crée ton compte"
            SignIn -> "Ravi de te revoir !"
        }

    val subtitle: String
        get() = when (this) {
            SignUp -> "pour commencer à raconter ton histoire"
            SignIn -> "connecte-toi"
        }
}
