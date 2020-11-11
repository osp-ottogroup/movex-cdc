<template>
  <b-modal id="condition-modal"
           :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card">
      <b-loading :active="isLoading" :is-full-page="false"/>

      <header class="modal-card-head">
        <p class="modal-card-title">{{title}}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>

      <section class="modal-card-body">
        <b-field label="Condition">
          <b-input ref="infoTextarea"
                   type="textarea"
                   rows="15"
                   v-model="conditionCode"/>
        </b-field>
      </section>

      <footer class="modal-card-foot" :class="!removable ? 'flex-end' : 'space-between'">
        <b-button v-if="removable"
                  id="delete-table-button"
                  type="is-danger"
                  @click="onRemove">
          Remove condition
        </b-button>
        <b-button id="save-table-button"
                  type="is-primary"
                  :disabled="!savable"
                  @click="onSave">
          Save
        </b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'ConditionModal',
  props: {
    condition: { type: Object, default: () => {} },
  },
  data() {
    return {
      isLoading: false,
      conditionCode: this.condition.filter,
    };
  },
  computed: {
    title() {
      let title = null;
      switch (this.condition.operation) {
        case 'I':
          title = 'Edit condition for insert-trigger';
          break;
        case 'U':
          title = 'Edit condition for update-trigger';
          break;
        case 'D':
          title = 'Edit condition for delete-trigger';
          break;
        default:
          throw new Error(`trigger type ${this.condition.operation} is not supported`);
      }
      return title;
    },
    removable() {
      return this.condition.id !== undefined;
    },
    savable() {
      return this.conditionCode !== '';
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    async onSave() {
      try {
        this.isLoading = true;
        let condition = { ...this.condition, filter: this.conditionCode };
        if (condition.id === undefined) {
          condition = await CRUDService.conditions.create(condition);
        } else {
          condition = await CRUDService.conditions.update(condition.id, condition);
        }
        this.$emit('saved', condition);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onRemove() {
      try {
        this.isLoading = true;
        await CRUDService.conditions.delete(this.condition.id, this.condition);
        this.$emit('removed', this.condition);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>

<style lang="scss" scoped>
  .space-between {
    justify-content: space-between;
  }
  .flex-end {
    justify-content: flex-end;
  }
</style>
