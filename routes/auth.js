import express from "express";
const router = express.Router();
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { db } from "../database.js";
import sendEmail from "../functions/sendEmail.js";
import emailHTML from "../email/emailHTML.js";
import { rateLimit } from "express-rate-limit";
import User from "../models/user.js";


const authLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
});

// Numero di iterazioni (cost) per bcrypt
const saltRounds = 10;

router.post("/register", authLimiter, async (req, res) => {
  const { username, password, email } = req.body;

  // 1. Verifica se l'input è valido (convalida di base)
  if (!username || !password || !email) {
    return res.status(400).send("Username, password ed email sono obbligatori.");
  }

  if (!email.match(/([@])\w+/g)) {
    return res.status(400).send("Email non valida.");
  }

  if (password.length < 8) {
    return res.status(400).send("La password deve avere almeno 8 caratteri.");
  }

  // 2. Controlla se l'utente esiste già nel database
  const existingUser = await db.any(`SELECT * FROM users WHERE username = $1`, [username])
  if (existingUser[0]) {
    return res.status(400).send("Questo nome utente è già registrato.");
  }

  try {
    const hashedPassword = await bcrypt.hash(password, saltRounds);
    const token = jwt.sign({ verifyemail: true }, process.env.SECRET_KEY);
    await db.func('create_user', [username, hashedPassword, email])
      .then(async (data) => {
        console.log("An user has been created");
        await db.any(
          "UPDATE users SET verification_token = $2 WHERE id = $1",
          [data[0].create_user, token]
        );
        sendEmail(email.toString(), "Registration confirmation", "Confirm your email address", emailHTML(token));
        return res.status(200).send("Registrazione completata con successo!");
      })
      .catch(error => {
        console.log('ERROR:', error);
      })
  } catch (error) {
    console.error("Errore durante la registrazione:", error);
    res.status(500).send("Errore del server. Riprova più tardi.");
  }
});

router.post('/login', authLimiter, async (req, res) => {
  const username = req.body.username;
  const password = req.body.password

  const _user = await db.oneOrNone(`SELECT id, password FROM users WHERE username = $1`, [username]);
  if (!_user) return res.status(400).send('Utente non trovato.');

  const isValidPassword = await bcrypt.compare(password, _user.password);
  if (!isValidPassword) return res.status(401).send('Password errata.');

  const user = new User(_user.id);
  const user_id = user.id
  await user.fetchInfo()

  // Crea un token JWT
  const token = jwt.sign({
    username: user.username,
    user_id: user_id,
    is_artist: user.isArtist,
    subscription: user.subscription
  }, process.env.SECRET_KEY, { expiresIn: "30d" });

  // Invia il token al client
  if (user.isVerified) {
    return res.json({
      token,
      username: user.username,
      user_id,
      is_artist: user.isArtist,
      subscription: user.subscription,
      is_verified: user.isVerified
    });
  } else {
    return res.status(403).json({ is_verified: user.isVerified });
  }
});

export default router;
