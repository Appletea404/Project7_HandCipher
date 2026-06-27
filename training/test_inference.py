import argparse
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

from training_emnist import EmnistDataset


def read_int8_hex(path, shape):
    """
    $readmemh용 2자리 hex txt를 signed int8 numpy 배열로 읽는다.

    파일에는 ff 같은 unsigned hex 문자열이 들어 있지만,
    weight는 signed int8이므로 np.int8로 다시 해석한다.
    """
    values = []
    with Path(path).open() as f:
        for line in f:
            token = line.strip()
            if not token:
                continue
            value = int(token, 16)
            if value >= 0x80:
                value -= 0x100
            values.append(value)

    array = np.array(values, dtype=np.int8)
    return array.reshape(shape)


def read_int32_hex(path, shape):
    """
    $readmemh용 8자리 hex txt를 signed int32 numpy 배열로 읽는다.

    bias는 accumulator에 더해질 signed int32 값이다.
    """
    values = []
    with Path(path).open() as f:
        for line in f:
            token = line.strip()
            if not token:
                continue
            value = int(token, 16)
            if value >= 0x80000000:
                value -= 0x100000000
            values.append(value)

    array = np.array(values, dtype=np.int32)
    return array.reshape(shape)


def load_exported_weights(export_dir):
    """
    quantize_export.py가 만든 txt 파일들을 읽는다.

    shape은 training 모델 구조와 RTL 계약에 맞춘다.
    - L1: 64 outputs x 784 inputs
    - L2: 26 outputs x 64 hidden values
    """
    export_dir = Path(export_dir)

    weights = {
        'w1': read_int8_hex(export_dir / 'weights_l1.mem', (64, 784)),
        'w2': read_int8_hex(export_dir / 'weights_l2.mem', (26, 64)),
        'b1': read_int32_hex(export_dir / 'biases_l1.mem', (64,)),
        'b2': read_int32_hex(export_dir / 'biases_l2.mem', (26,)),
    }

    return weights


def infer_integer_batch(images, weights, shift_l1):
    """
    RTL NPU와 같은 방식으로 batch 정수 추론을 수행한다.

    입력 images는 PyTorch tensor이며 값 범위는 0.0~1.0이다.
    RTL에서는 canvas pixel을 uint8로 다룰 예정이므로 여기서 0~255로 변환한다.

    계산식:
        acc1   = sum(pixel_uint8 * w1_int8) + b1_int32
        hidden = clamp(relu(acc1 >> SHIFT_L1), 0, 255)
        score  = sum(hidden_uint8 * w2_int8) + b2_int32
        pred   = argmax(score)
    """
    x = images.numpy()
    x = np.round(x * 255.0).astype(np.uint8)
    x = x.reshape(x.shape[0], 784).astype(np.int32)

    w1 = weights['w1'].astype(np.int32)
    w2 = weights['w2'].astype(np.int32)
    b1 = weights['b1'].astype(np.int32)
    b2 = weights['b2'].astype(np.int32)

    # [batch, 784] @ [784, 64] -> [batch, 64]
    acc1 = x @ w1.T + b1

    # Verilog의 signed arithmetic shift와 같은 의미로 numpy right shift를 사용한다.
    hidden = acc1 >> shift_l1
    hidden = np.maximum(hidden, 0)
    hidden = np.minimum(hidden, 255).astype(np.uint8)

    # [batch, 64] @ [64, 26] -> [batch, 26]
    scores = hidden.astype(np.int32) @ w2.T + b2
    preds = np.argmax(scores, axis=1)

    return preds


def evaluate_integer(data_dir, export_dir, batch_size, shift_l1, max_batches):
    test_set = EmnistDataset(data_dir, train=False)
    loader = DataLoader(
        test_set,
        batch_size=batch_size,
        shuffle=False,
        num_workers=0,
    )

    weights = load_exported_weights(export_dir)

    correct = 0
    total = 0

    for batch_idx, (images, labels) in enumerate(tqdm(loader, desc='int eval')):
        preds = infer_integer_batch(images, weights, shift_l1)
        labels_np = labels.numpy()

        correct += int(np.sum(preds == labels_np))
        total += labels_np.shape[0]

        # 빠른 실험용 옵션. 전체 test set을 보려면 None으로 둔다.
        if max_batches is not None and batch_idx + 1 >= max_batches:
            break

    return correct / total, correct, total


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-dir', default='./data')
    parser.add_argument('--export-dir', default='./exported')
    parser.add_argument('--batch-size', type=int, default=256)
    parser.add_argument('--shift-l1', type=int, default=10)
    parser.add_argument('--max-batches', type=int, default=None)
    args = parser.parse_args()

    acc, correct, total = evaluate_integer(
        data_dir=args.data_dir,
        export_dir=args.export_dir,
        batch_size=args.batch_size,
        shift_l1=args.shift_l1,
        max_batches=args.max_batches,
    )

    print(f'integer accuracy: {acc * 100:.2f}% ({correct}/{total})')

    if acc >= 0.80:
        print('PASS: integer accuracy target reached')
    else:
        print('WARN: integer accuracy is below 80%; quantization tuning is needed')


if __name__ == '__main__':
    main()
