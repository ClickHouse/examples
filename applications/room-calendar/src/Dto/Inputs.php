<?php

declare(strict_types=1);

namespace App\Dto;

use App\ApiProblem;
use Symfony\Component\Validator\Constraints as Assert;
use Symfony\Component\Validator\Validator\ValidatorInterface;

final readonly class Inputs
{
    public function __construct(private ValidatorInterface $validator) {}

    public function fields(array $values, array $required): void
    {
        if (array_diff(array_keys($values), $required) || array_diff($required, array_keys($values))) {
            throw new ApiProblem(400, 'Missing or unknown request fields.');
        }
    }

    public function uuid(mixed $value): string
    {
        if (!is_string($value) || count($this->validator->validate($value, new Assert\Uuid())) !== 0) {
            throw new ApiProblem(400, 'A UUID is required.');
        }
        return strtolower($value);
    }

    public function title(mixed $value): string
    {
        if (count($this->validator->validate($value,
                [new Assert\Type('string'), new Assert\NotBlank(), new Assert\Length(max: 120)])) !== 0
            || !is_string($value) || preg_match('/\p{C}/u', $value) !== 0) {
            throw new ApiProblem(400, 'Title must be nonblank text of at most 120 characters without controls.');
        }
        return $value;
    }

    public function revision(mixed $value): int
    {
        if (!is_int($value) || count($this->validator->validate($value,
                new Assert\Range(min: 1,max: 1000000000))) !== 0) {
            throw new ApiProblem(400, 'Expected revision must be an integer from 1 to 1000000000.');
        }
        return $value;
    }
}
