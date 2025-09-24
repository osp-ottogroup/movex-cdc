<template>
  <b-modal :active="show" @close="$emit('close')">
    <div class="modal-card">
      <header class="modal-card-head">
        <p class="modal-card-title">Edit Column Expression</p>
        <button class="delete" @click="$emit('close')"></button>
      </header>
      <section class="modal-card-body">
        <b-field label="SQL Expression">
          <b-input v-model="localExpression.sql" type="textarea" rows="6" />
        </b-field>
      </section>
      <footer class="modal-card-foot">
        <b-button type="is-primary" @click="onSave">Save</b-button>
        <b-button type="is-danger" @click="onRemove" v-if="localExpression.id">Remove</b-button>
        <b-button @click="$emit('close')">Cancel</b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
export default {
  name: 'EditColumnExpressionModal',
  props: {
    show: Boolean,
    expression: Object,
  },
  data() {
    return {
      localExpression: { ...this.expression },
    };
  },
  watch: {
    expression(newVal) {
      this.localExpression = { ...newVal };
    },
  },
  methods: {
    onSave() {
      this.$emit('save', this.localExpression);
    },
    onRemove() {
      this.$emit('remove', this.localExpression);
    },
  },
};
</script>
