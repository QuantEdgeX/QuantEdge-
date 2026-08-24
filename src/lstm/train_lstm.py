import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, f1_score
from sklearn.utils.class_weight import compute_class_weight
 
from src.lstm.prepare_sequences import prepare_sequences


def build_model(input_shape):
    reg = tf.keras.regularizers.l2(1e-4)

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=input_shape),

        tf.keras.layers.LSTM(
            64,
            return_sequences=True,
            recurrent_dropout=0.1,
            kernel_regularizer=reg
        ),
        tf.keras.layers.Dropout(0.3),

        tf.keras.layers.LSTM(
            32,
            recurrent_dropout=0.1,
            kernel_regularizer=reg
        ),
        tf.keras.layers.Dropout(0.3),

        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dense(16, activation="relu", kernel_regularizer=reg),
        tf.keras.layers.Dropout(0.2),

        tf.keras.layers.Dense(3, activation="softmax"),
    ])

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def macro_f1(y_true, y_pred):
    return f1_score(y_true, y_pred, average="macro")


def train():
    (
        X_train, y_train,
        X_val, y_val,
        X_test, y_test,
        scalers
    ) = prepare_sequences()

    print("\n========== BUILDING LSTM ==========")
    print("Input shape:", X_train.shape[1:])

    classes = np.unique(y_train)
    weights = compute_class_weight(class_weight="balanced", classes=classes, y=y_train)
    class_weights = dict(zip(classes, weights))
    print("\nClass weights:")
    print(class_weights)

    model = build_model(input_shape=X_train.shape[1:])
    model.summary()

    early_stopping = tf.keras.callbacks.EarlyStopping(
        monitor="val_loss",
        patience=10,
        restore_best_weights=True,
    )
    reduce_lr = tf.keras.callbacks.ReduceLROnPlateau(
        monitor="val_loss",
        factor=0.5,
        patience=4,
        min_lr=1e-6,
        verbose=1,
    )
    model_checkpoint = tf.keras.callbacks.ModelCheckpoint(
        "best_lstm_model.keras",
        monitor="val_loss",
        save_best_only=True,
    )

    print("\n========== TRAINING LSTM ==========")
    model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=100,
        batch_size=32,
        class_weight=class_weights,
        callbacks=[early_stopping, reduce_lr, model_checkpoint],
        verbose=1,
    )

    print("\n========== FINAL EVALUATION ==========")
    test_loss, test_accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"Test Loss: {test_loss:.4f}")
    print(f"Test Accuracy: {test_accuracy:.4f}")

    probabilities = model.predict(X_test, verbose=0)
    y_pred = np.argmax(probabilities, axis=1)

    print(f"Test Macro-F1: {macro_f1(y_test, y_pred):.4f}")
    # Macro-F1 matters more than accuracy here: with 3 classes and one
    # (HOLD) usually smaller, a model that only predicts BUY/SELL can
    # still post decent accuracy while being useless for HOLD detection.

    print("\n========== CLASSIFICATION REPORT ==========")
    print(classification_report(y_test, y_pred, target_names=["BUY", "HOLD", "SELL"]))

    print("\n========== CONFUSION MATRIX ==========")
    print(confusion_matrix(y_test, y_pred))

    model.save("lstm_model.keras")
    print("\nLSTM model saved!")


if __name__ == "__main__":
    train()